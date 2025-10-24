import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/live_channel.dart';
import '../models/live_source.dart';
import '../models/epg_program.dart';
import '../services/api_service.dart';
import '../widgets/mobile_video_player_widget.dart';
import '../widgets/pc_video_player_widget.dart';
import '../utils/device_utils.dart';
import '../utils/font_utils.dart';
import '../services/theme_service.dart';
import 'package:provider/provider.dart';
import '../widgets/windows_title_bar.dart';
import '../widgets/switch_loading_overlay.dart';

class LivePlayerScreen extends StatefulWidget {
  final LiveChannel channel;
  final LiveSource source;

  const LivePlayerScreen({
    super.key,
    required this.channel,
    required this.source,
  });

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen>
    with TickerProviderStateMixin {
  late SystemUiOverlayStyle _originalStyle;
  bool _isInitialized = false;
  late LiveChannel _currentChannel;
  late LiveSource _currentSource;
  List<EpgProgram>? _programs;
  bool _isLoadingEpg = false;
  List<LiveChannel> _allChannels = [];

  // 缓存设备类型
  late bool _isTablet;
  late bool _isPortraitTablet;

  // 播放器控制器
  MobileVideoPlayerWidgetController? _mobileVideoPlayerController;
  PcVideoPlayerWidgetController? _pcVideoPlayerController;

  // 播放器的 GlobalKey
  final GlobalKey _playerKey = GlobalKey();

  // 当前节目的 GlobalKey，用于滚动定位
  final GlobalKey _currentProgramKey = GlobalKey();

  // 当前频道的 GlobalKey，用于滚动定位
  final GlobalKey _currentChannelKey = GlobalKey();

  // 节目单滚动控制器
  final ScrollController _programScrollController = ScrollController();

  // 网页全屏状态
  bool _isWebFullscreen = false;

  // 加载状态
  bool _isLoading = true;
  String _loadingMessage = '正在加载直播频道...';
  late AnimationController _loadingAnimationController;

  @override
  void initState() {
    super.initState();
    _currentChannel = widget.channel;
    _currentSource = widget.source;

    // 初始化动画控制器
    _loadingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_isInitialized) {
      // 缓存设备类型 - 在这里调用是安全的，因为 MediaQuery 已经可用
      _isTablet = DeviceUtils.isTablet(context);
      _isPortraitTablet = DeviceUtils.isPortraitTablet(context);

      // 保存当前的系统UI样式
      final theme = Theme.of(context);
      final isDarkMode = theme.brightness == Brightness.dark;
      _originalStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
      );
      _isInitialized = true;

      // 加载数据
      _loadAllChannels();
      _loadEpgData();
    }
  }

  Future<void> _loadAllChannels() async {
    try {
      final channels = await ApiService.getLiveChannels(_currentSource.key);
      if (mounted) {
        setState(() {
          _allChannels = channels;
        });

        // 滚动到当前频道
        _scrollToCurrentChannel();
      }
    } catch (e) {
      print('加载频道列表失败: $e');
      if (mounted) {
        setState(() {
          _allChannels = [];
        });
      }
    }
  }

  void _switchChannel(LiveChannel channel) {
    setState(() {
      _currentChannel = channel;
      _isLoading = true;
      _loadingMessage = '切换频道...';
    });

    // 重新加载 EPG
    _loadEpgData();

    // 滚动到当前频道
    _scrollToCurrentChannel();
  }

  @override
  void dispose() {
    // 恢复原始的系统UI样式
    SystemChrome.setSystemUIOverlayStyle(_originalStyle);
    _programScrollController.dispose();
    _loadingAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadEpgData() async {
    setState(() {
      _isLoadingEpg = true;
    });

    try {
      // 如果 tvgId 为空，则不加载 EPG
      if (_currentChannel.tvgId.isEmpty) {
        if (mounted) {
          setState(() {
            _programs = null;
            _isLoadingEpg = false;
          });
        }
        return;
      }

      // 调用 ApiService 获取 EPG 数据
      final epgData = await ApiService.getLiveEpg(
        _currentChannel.tvgId,
        _currentSource.key,
      );

      if (mounted) {
        setState(() {
          _programs = epgData?.programs;
          _isLoadingEpg = false;
        });

        // 滚动到当前节目
        _scrollToCurrentProgram();
      }
    } catch (e) {
      print('加载 EPG 失败: $e');
      if (mounted) {
        setState(() {
          _programs = null;
          _isLoadingEpg = false;
        });
      }
    }
  }

  // 退出网页全屏
  void _exitWebFullscreen() {
    if (!DeviceUtils.isPC()) {
      return;
    }
    // 通知播放器控件退出网页全屏
    // 播放器控件会通过 onWebFullscreenChanged 回调来更新 _isWebFullscreen 状态
    if (_pcVideoPlayerController != null) {
      _pcVideoPlayerController!.exitWebFullscreen();
    }
  }

  /// 处理视频播放器 ready 事件
  void _onVideoPlayerReady() {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 滚动到当前正在播放的节目
  void _scrollToCurrentProgram() {
    if (_programs == null || _programs!.isEmpty) return;

    // 找到当前正在播放的节目索引
    final currentIndex = _programs!.indexWhere((p) => p.isLive);
    if (currentIndex == -1) return;

    // 延迟执行，确保列表已经渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_programScrollController.hasClients) return;

      // 计算节目项的精确高度
      // padding: 12 (top) + 12 (bottom) = 24
      // margin: 12 (bottom) = 12
      // 内容高度估算：
      // - 时间行: ~20 (包括 badge 或纯文本)
      // - 间距: 6
      // - 标题: ~20
      // - 描述(如果有): ~30
      // - 进度条(如果是直播): ~16
      // 基础高度 = 24 + 12 + 20 + 6 + 20 = 82
      // 有描述时 += 34 (4间距 + 30高度)
      // 有进度条时 += 12 (8间距 + 4高度)

      // 使用保守估计，每个项目约 110 像素(包含描述的情况)
      const double baseItemHeight = 82.0;
      const double descriptionHeight = 34.0;
      const double progressHeight = 12.0;

      // 计算到目标节目的累计高度
      double totalOffset = 0.0;
      for (int i = 0; i < currentIndex; i++) {
        double itemHeight = baseItemHeight;
        if (_programs![i].description != null &&
            _programs![i].description!.isNotEmpty) {
          itemHeight += descriptionHeight;
        }
        if (_programs![i].isLive) {
          itemHeight += progressHeight;
        }
        totalOffset += itemHeight;
      }

      // 获取可视区域高度,将当前节目定位在屏幕中央偏上位置
      final viewportHeight =
          _programScrollController.position.viewportDimension;
      final centerOffset = totalOffset - (viewportHeight * 0.3);

      // 确保不会滚动到负值或超出最大滚动范围
      final maxScrollExtent = _programScrollController.position.maxScrollExtent;
      final clampedOffset = centerOffset.clamp(0.0, maxScrollExtent);

      // 滚动到目标位置
      _programScrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  /// 滚动到当前频道
  void _scrollToCurrentChannel() {
    if (_allChannels.isEmpty) return;

    // 延迟执行，确保列表已经渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 使用 Scrollable.ensureVisible 滚动到当前频道
      final context = _currentChannelKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.25, // 将当前频道显示在屏幕上方 25% 的位置，留出更多空间显示下方频道
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final themeService = context.watch<ThemeService>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor:
            isDarkMode ? Colors.black : theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness:
            isDarkMode ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: isDarkMode
                ? null
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFe6f3fb),
                      Color(0xFFeaf3f7),
                      Color(0xFFf7f7f3),
                      Color(0xFFe9ecef),
                      Color(0xFFdbe3ea),
                      Color(0xFFd3dde6),
                    ],
                    stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
                  ),
            color: isDarkMode ? theme.scaffoldBackgroundColor : null,
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  // Windows 自定义标题栏
                  if (Platform.isWindows)
                    const WindowsTitleBar(
                      customBackgroundColor: Color(0xFF000000),
                    ),
                  // 主要内容
                  Expanded(
                    child: Stack(
                      children: [
                        // 主要内容（不包含播放器）
                        if (!_isWebFullscreen)
                          if (_isTablet && !_isPortraitTablet)
                            _buildTabletLandscapeLayout(theme, themeService)
                          else if (_isPortraitTablet)
                            _buildPortraitTabletLayout(theme, themeService)
                          else
                            _buildPhoneLayout(theme, themeService),
                        // 播放器层
                        _buildPlayerLayer(theme),
                      ],
                    ),
                  ),
                ],
              ),
              // 状态栏黑色背景（覆盖在最上层）
              if (!Platform.isWindows)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).padding.top,
                  child: Container(
                    color: Colors.black,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建播放器层
  Widget _buildPlayerLayer(ThemeData theme) {
    final statusBarHeight = MediaQuery.maybeOf(context)?.padding.top ?? 0;
    final macOSPadding = DeviceUtils.isMacOS() ? 32.0 : 0.0;
    final topOffset = statusBarHeight + macOSPadding;

    if (_isWebFullscreen) {
      // 网页全屏模式：播放器占据整个屏幕（保留顶部安全区域）
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        child: Column(
          children: [
            // 顶部安全区域
            Container(
              height: topOffset,
              color: Colors.black,
            ),
            // 播放器
            Expanded(
              child: Stack(
                children: [
                  Container(
                    key: _playerKey,
                    color: Colors.black,
                    child: _buildPlayerWidget(),
                  ),
                  // 加载蒙版
                  _buildSwitchLoadingOverlay(),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // 非网页全屏模式：根据不同布局计算播放器位置
      if (_isTablet && !_isPortraitTablet) {
        // 平板横屏模式：播放器在左侧65%区域
        final screenWidth = MediaQuery.of(context).size.width;
        final leftWidth = screenWidth * 0.65;
        final playerHeight = leftWidth / (16 / 9);

        return Positioned(
          top: topOffset,
          left: 0,
          width: leftWidth,
          height: playerHeight,
          child: Stack(
            children: [
              Container(
                key: _playerKey,
                color: Colors.black,
                child: _buildPlayerWidget(),
              ),
              // 加载蒙版
              _buildSwitchLoadingOverlay(),
            ],
          ),
        );
      } else if (_isPortraitTablet) {
        // 平板竖屏模式：播放器占50%高度
        final screenHeight = MediaQuery.of(context).size.height;
        final playerHeight = (screenHeight - topOffset) * 0.5;

        return Positioned(
          top: topOffset,
          left: 0,
          right: 0,
          height: playerHeight,
          child: Stack(
            children: [
              Container(
                key: _playerKey,
                color: Colors.black,
                child: _buildPlayerWidget(),
              ),
              // 加载蒙版
              _buildSwitchLoadingOverlay(),
            ],
          ),
        );
      } else {
        // 手机模式：16:9 比例
        final screenWidth = MediaQuery.of(context).size.width;
        final playerHeight = screenWidth / (16 / 9);

        return Positioned(
          top: topOffset,
          left: 0,
          right: 0,
          height: playerHeight,
          child: Stack(
            children: [
              Container(
                key: _playerKey,
                color: Colors.black,
                child: _buildPlayerWidget(),
              ),
              // 加载蒙版
              _buildSwitchLoadingOverlay(),
            ],
          ),
        );
      }
    }
  }

  /// 构建播放器组件
  Widget _buildPlayerWidget() {
    final videoUrl = _currentChannel.url;

    if (DeviceUtils.isPC()) {
      return PcVideoPlayerWidget(
        key: ValueKey(_currentChannel.id),
        url: videoUrl,
        headers: <String, String>{
          'User-Agent': _currentSource.ua.isNotEmpty
              ? _currentSource.ua
              : 'AptvPlayer/1.4.10',
        },
        videoTitle: _currentChannel.name,
        onBackPressed: _isWebFullscreen
            ? _exitWebFullscreen
            : () => Navigator.pop(context),
        onControllerCreated: (controller) {
          _pcVideoPlayerController = controller;
        },
        onWebFullscreenChanged: (isWebFullscreen) {
          setState(() {
            _isWebFullscreen = isWebFullscreen;
          });
        },
        onReady: _onVideoPlayerReady,
        live: true,
      );
    } else {
      return MobileVideoPlayerWidget(
        key: ValueKey(_currentChannel.id),
        url: videoUrl,
        headers: <String, String>{
          'User-Agent': _currentSource.ua.isNotEmpty
              ? _currentSource.ua
              : 'AptvPlayer/1.4.10',
        },
        videoTitle: _currentChannel.name,
        onBackPressed: () => Navigator.pop(context),
        onControllerCreated: (controller) {
          _mobileVideoPlayerController = controller;
        },
        onReady: _onVideoPlayerReady,
        live: true,
      );
    }
  }

  /// 构建手机模式布局
  Widget _buildPhoneLayout(ThemeData theme, ThemeService themeService) {
    final statusBarHeight = MediaQuery.maybeOf(context)?.padding.top ?? 0;
    final macOSPadding = DeviceUtils.isMacOS() ? 32.0 : 0.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final playerHeight = screenWidth / (16 / 9);

    return Column(
      children: [
        // macOS/状态栏黑色背景
        Container(
          height: statusBarHeight + macOSPadding,
          color: Colors.black,
        ),
        // 播放器占位
        SizedBox(height: playerHeight),
        _buildChannelInfo(theme, themeService),
        _buildSourceSelector(theme, themeService),
        Expanded(
          child: _buildProgramGuideScrollable(theme, themeService),
        ),
      ],
    );
  }

  /// 构建平板横屏布局
  Widget _buildTabletLandscapeLayout(
      ThemeData theme, ThemeService themeService) {
    final statusBarHeight = MediaQuery.maybeOf(context)?.padding.top ?? 0;
    final macOSPadding = DeviceUtils.isMacOS() ? 32.0 : 0.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final leftWidth = screenWidth * 0.65;
    final playerHeight = leftWidth / (16 / 9);

    return Column(
      children: [
        // macOS/状态栏黑色背景
        Container(
          height: statusBarHeight + macOSPadding,
          color: Colors.black,
        ),
        Expanded(
          child: Row(
            children: [
              // 左侧：播放器、台标台名和节目单
              SizedBox(
                width: leftWidth,
                child: Column(
                  children: [
                    // 播放器占位
                    SizedBox(height: playerHeight),
                    // 台标台名放在播放器下方
                    _buildChannelInfo(theme, themeService),
                    // 节目单
                    Expanded(
                      child: _buildProgramGuideScrollable(theme, themeService),
                    ),
                  ],
                ),
              ),
              // 右侧：播放源和频道列表
              Expanded(
                child: Container(
                  color: themeService.isDarkMode
                      ? const Color(0xFF1e1e1e)
                      : Colors.white,
                  child: Column(
                    children: [
                      // 顶部栏
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: themeService.isDarkMode
                                  ? const Color(0xFF333333)
                                  : const Color(0xFFe0e0e0),
                            ),
                          ),
                        ),
                        child: Text(
                          '频道列表',
                          style: FontUtils.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: themeService.isDarkMode
                                ? Colors.white
                                : const Color(0xFF2c3e50),
                          ),
                        ),
                      ),
                      // 内容区域
                      Expanded(
                        child: Column(
                          children: [
                            // 播放源选择器
                            _buildSourceSelector(theme, themeService),
                            // 频道列表
                            Expanded(
                              child: _buildChannelList(theme, themeService),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建平板竖屏布局
  Widget _buildPortraitTabletLayout(
      ThemeData theme, ThemeService themeService) {
    final statusBarHeight = MediaQuery.maybeOf(context)?.padding.top ?? 0;
    final macOSPadding = DeviceUtils.isMacOS() ? 32.0 : 0.0;
    final screenHeight = MediaQuery.of(context).size.height;
    final playerHeight = (screenHeight - statusBarHeight - macOSPadding) * 0.5;

    return Column(
      children: [
        // macOS/状态栏黑色背景
        Container(
          height: statusBarHeight + macOSPadding,
          color: Colors.black,
        ),
        // 播放器占位
        SizedBox(height: playerHeight),
        // 台标台名（固定）
        _buildChannelInfo(theme, themeService),
        // 播放源选择器（固定）
        _buildSourceSelector(theme, themeService),
        // 节目单（可滚动）
        Expanded(
          child: _buildProgramGuideScrollable(theme, themeService),
        ),
      ],
    );
  }

  /// 构建频道信息
  Widget _buildChannelInfo(ThemeData theme, ThemeService themeService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeService.isDarkMode ? const Color(0xFF1e1e1e) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: themeService.isDarkMode
                ? const Color(0xFF333333)
                : const Color(0xFFe0e0e0),
          ),
        ),
      ),
      child: Row(
        children: [
          // 台标
          if (_currentChannel.logo.isNotEmpty)
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: themeService.isDarkMode
                    ? const Color(0xFF2a2a2a)
                    : const Color(0xFFf5f5f5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  _currentChannel.logo,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return _buildDefaultLogoIcon();
                  },
                ),
              ),
            )
          else
            _buildDefaultLogo(),
          const SizedBox(width: 16),
          // 频道信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _currentChannel.name,
                        style: FontUtils.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: themeService.isDarkMode
                              ? Colors.white
                              : const Color(0xFF2c3e50),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _currentChannel.group,
                  style: FontUtils.poppins(
                    fontSize: 14,
                    color: themeService.isDarkMode
                        ? const Color(0xFF999999)
                        : const Color(0xFF7f8c8d),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF27ae60).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.tv,
        size: 32,
        color: Color(0xFF27ae60),
      ),
    );
  }

  Widget _buildDefaultLogoIcon() {
    return const Icon(
      Icons.tv,
      size: 32,
      color: Color(0xFF27ae60),
    );
  }

  /// 构建频道列表
  Widget _buildChannelList(ThemeData theme, ThemeService themeService) {
    if (_allChannels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '暂无频道',
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode
                  ? const Color(0xFF999999)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _allChannels.length,
      itemBuilder: (context, index) {
        final channel = _allChannels[index];
        final isSelected = channel.id == _currentChannel.id;

        // 只给当前频道添加 key，用于滚动定位
        final itemKey =
            isSelected ? _currentChannelKey : ValueKey('channel_${channel.id}');

        return ListTile(
          key: itemKey,
          selected: isSelected,
          selectedTileColor: const Color(0xFF27ae60).withOpacity(0.1),
          leading: channel.logo.isNotEmpty
              ? Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: themeService.isDarkMode
                        ? const Color(0xFF2a2a2a)
                        : const Color(0xFFf5f5f5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      channel.logo,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.tv,
                          size: 20,
                          color: Color(0xFF27ae60),
                        );
                      },
                    ),
                  ),
                )
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF27ae60).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.tv,
                    size: 20,
                    color: Color(0xFF27ae60),
                  ),
                ),
          title: Text(
            channel.name,
            style: FontUtils.poppins(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? const Color(0xFF27ae60)
                  : themeService.isDarkMode
                      ? Colors.white
                      : const Color(0xFF2c3e50),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            channel.group,
            style: FontUtils.poppins(
              fontSize: 12,
              color: themeService.isDarkMode
                  ? const Color(0xFF999999)
                  : const Color(0xFF7f8c8d),
            ),
          ),
          onTap: () => _switchChannel(channel),
        );
      },
    );
  }

  /// 构建播放源选择器（新结构不再需要多源选择）
  Widget _buildSourceSelector(ThemeData theme, ThemeService themeService) {
    return const SizedBox.shrink();
  }

  /// 构建可滚动的节目单（用于平板横屏）
  Widget _buildProgramGuideScrollable(
      ThemeData theme, ThemeService themeService) {
    return Container(
      decoration: BoxDecoration(
        color: themeService.isDarkMode ? const Color(0xFF1e1e1e) : Colors.white,
        border: Border(
          top: BorderSide(
            color: themeService.isDarkMode
                ? const Color(0xFF333333)
                : const Color(0xFFe0e0e0),
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏（固定）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: themeService.isDarkMode
                      ? const Color(0xFF333333)
                      : const Color(0xFFe0e0e0),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '节目单',
                  style: FontUtils.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: themeService.isDarkMode
                        ? Colors.white
                        : const Color(0xFF2c3e50),
                  ),
                ),
                const Spacer(),
                if (_isLoadingEpg)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF27ae60)),
                    ),
                  ),
              ],
            ),
          ),
          // 节目列表（可滚动）
          Expanded(
            child: _buildProgramList(themeService),
          ),
        ],
      ),
    );
  }

  /// 构建节目列表
  Widget _buildProgramList(ThemeService themeService) {
    if (_isLoadingEpg) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '加载节目单中...',
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode
                  ? const Color(0xFF999999)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ),
      );
    }

    if (_programs == null || _programs!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 48,
                color: themeService.isDarkMode
                    ? const Color(0xFF666666)
                    : const Color(0xFF95a5a6),
              ),
              const SizedBox(height: 12),
              Text(
                '暂无节目单信息',
                style: FontUtils.poppins(
                  fontSize: 14,
                  color: themeService.isDarkMode
                      ? const Color(0xFF999999)
                      : const Color(0xFF7f8c8d),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _programScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _programs!.length,
      itemBuilder: (context, index) {
        final program = _programs![index];
        return _buildProgramItem(
          program,
          themeService,
          key: program.isLive ? _currentProgramKey : null,
        );
      },
    );
  }

  Widget _buildProgramItem(
    EpgProgram program,
    ThemeService themeService, {
    Key? key,
  }) {
    final isLive = program.isLive;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLive
            ? const Color(0xFF27ae60).withOpacity(0.1)
            : themeService.isDarkMode
                ? const Color(0xFF2a2a2a)
                : const Color(0xFFf5f5f5),
        borderRadius: BorderRadius.circular(8),
        border: isLive
            ? Border.all(color: const Color(0xFF27ae60), width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isLive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF27ae60),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '直播中',
                    style: FontUtils.poppins(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (isLive) const SizedBox(width: 8),
              Text(
                program.timeRange,
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isLive
                      ? const Color(0xFF27ae60)
                      : themeService.isDarkMode
                          ? const Color(0xFF999999)
                          : const Color(0xFF7f8c8d),
                  fontWeight: isLive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            program.title,
            style: FontUtils.poppins(
              fontSize: 14,
              fontWeight: isLive ? FontWeight.w600 : FontWeight.w500,
              color: themeService.isDarkMode
                  ? Colors.white
                  : const Color(0xFF2c3e50),
            ),
          ),
          if (program.description != null &&
              program.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              program.description!,
              style: FontUtils.poppins(
                fontSize: 12,
                color: themeService.isDarkMode
                    ? const Color(0xFF999999)
                    : const Color(0xFF7f8c8d),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (isLive) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: program.progress,
                backgroundColor: themeService.isDarkMode
                    ? const Color(0xFF333333)
                    : const Color(0xFFe0e0e0),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF27ae60),
                ),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建切换加载蒙版（只覆盖播放器）
  Widget _buildSwitchLoadingOverlay() {
    return SwitchLoadingOverlay(
      isVisible: _isLoading,
      message: _loadingMessage,
      animationController: _loadingAnimationController,
      onBackPressed:
          _isWebFullscreen ? _exitWebFullscreen : () => Navigator.pop(context),
    );
  }
}
