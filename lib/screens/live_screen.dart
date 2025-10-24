import 'package:flutter/material.dart';
import '../models/live_channel.dart';
import '../models/live_source.dart';
import '../services/api_service.dart';
import '../utils/font_utils.dart';
import '../services/theme_service.dart';
import 'package:provider/provider.dart';
import 'live_player_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  List<LiveChannelGroup> _channelGroups = [];
  List<LiveSource> _liveSources = [];
  LiveSource? _currentSource;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedGroup = '全部';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadChannels({LiveSource? source}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. 获取所有直播源
      final liveSources = await ApiService.getLiveSources();

      if (liveSources.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '暂无直播源，请在 MoonTV 添加';
            _isLoading = false;
            _liveSources = [];
            _currentSource = null;
          });
        }
        return;
      }

      // 2. 确定要使用的直播源
      final targetSource = source ?? _currentSource ?? liveSources.first;

      // 3. 获取该直播源的频道列表
      final channels = await ApiService.getLiveChannels(targetSource.key);

      if (channels.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '该直播源暂无频道';
            _isLoading = false;
            _liveSources = liveSources;
            _currentSource = targetSource;
          });
        }
        return;
      }

      // 4. 按 group 进行聚类
      final Map<String, List<LiveChannel>> groupedChannels = {};
      for (var channel in channels) {
        final groupName = channel.group.isEmpty ? '未分组' : channel.group;
        if (!groupedChannels.containsKey(groupName)) {
          groupedChannels[groupName] = [];
        }
        groupedChannels[groupName]!.add(channel);
      }

      // 5. 转换为 LiveChannelGroup 列表
      final groups = groupedChannels.entries
          .map((entry) => LiveChannelGroup(
                name: entry.key,
                channels: entry.value,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _liveSources = liveSources;
          _currentSource = targetSource;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> refreshChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. 重新获取所有直播源
      final liveSources = await ApiService.getLiveSources();

      if (liveSources.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '暂无直播源，请在 MoonTV 添加';
            _isLoading = false;
            _liveSources = [];
            _currentSource = null;
          });
        }
        return;
      }

      // 2. 检查当前源是否还存在
      LiveSource? targetSource;
      if (_currentSource != null) {
        // 尝试在新的源列表中找到当前源
        try {
          targetSource = liveSources.firstWhere(
            (source) => source.key == _currentSource!.key,
          );
        } catch (e) {
          // 当前源不存在，使用第一个源
          targetSource = liveSources.first;
          if (mounted) {
            _showMessage('当前源已不存在，已切换到 ${targetSource.name}');
          }
        }
      } else {
        // 没有当前源，使用第一个源
        targetSource = liveSources.first;
      }

      // 3. 获取目标源的频道列表
      final channels = await ApiService.getLiveChannels(targetSource.key);

      if (channels.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '该直播源暂无频道';
            _isLoading = false;
            _liveSources = liveSources;
            _currentSource = targetSource;
          });
        }
        return;
      }

      // 4. 按 group 进行聚类
      final Map<String, List<LiveChannel>> groupedChannels = {};
      for (var channel in channels) {
        final groupName = channel.group.isEmpty ? '未分组' : channel.group;
        if (!groupedChannels.containsKey(groupName)) {
          groupedChannels[groupName] = [];
        }
        groupedChannels[groupName]!.add(channel);
      }

      // 5. 转换为 LiveChannelGroup 列表
      final groups = groupedChannels.entries
          .map((entry) => LiveChannelGroup(
                name: entry.key,
                channels: entry.value,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _liveSources = liveSources;
          _currentSource = targetSource;
          _isLoading = false;
        });
        _showMessage('刷新成功');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '刷新失败: $e';
          _isLoading = false;
        });
        _showMessage('刷新失败: $e');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: FontUtils.poppins(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF3498DB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// 显示切换源底部弹窗
  void _showSourceSwitchBottomSheet(ThemeService themeService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: themeService.isDarkMode
                ? const Color(0xFF1e1e1e)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: themeService.isDarkMode
                      ? const Color(0xFF666666)
                      : const Color(0xFFe0e0e0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      '选择直播源',
                      style: FontUtils.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: themeService.isDarkMode
                            ? Colors.white
                            : const Color(0xFF2c3e50),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${_liveSources.length} 个源',
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
              const Divider(height: 1),
              // 源列表
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _liveSources.length,
                  itemBuilder: (context, index) {
                    final source = _liveSources[index];
                    final isSelected = _currentSource?.key == source.key;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _loadChannels(source: source);
                        setState(() {
                          _selectedGroup = '全部';
                        });
                        _scrollToTop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3498DB).withValues(alpha: 0.1)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF3498DB)
                                    : themeService.isDarkMode
                                        ? const Color(0xFF2a2a2a)
                                        : const Color(0xFFf5f5f5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.live_tv,
                                  size: 20,
                                  color: isSelected
                                      ? Colors.white
                                      : themeService.isDarkMode
                                          ? const Color(0xFF999999)
                                          : const Color(0xFF7f8c8d),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.name,
                                    style: FontUtils.poppins(
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? const Color(0xFF3498DB)
                                          : themeService.isDarkMode
                                              ? Colors.white
                                              : const Color(0xFF2c3e50),
                                    ),
                                  ),
                                  if (source.channelNumber > 0)
                                    Text(
                                      '${source.channelNumber} 个频道',
                                      style: FontUtils.poppins(
                                        fontSize: 12,
                                        color: themeService.isDarkMode
                                            ? const Color(0xFF999999)
                                            : const Color(0xFF7f8c8d),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF3498DB),
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 显示更多分类底部弹窗
  void _showMoreGroupsBottomSheet(
      List<String> moreGroups, ThemeService themeService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: themeService.isDarkMode
                ? const Color(0xFF1e1e1e)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖动条
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: themeService.isDarkMode
                      ? const Color(0xFF666666)
                      : const Color(0xFFe0e0e0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      '选择分类',
                      style: FontUtils.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: themeService.isDarkMode
                            ? Colors.white
                            : const Color(0xFF2c3e50),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '共 ${moreGroups.length} 个分类',
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
              const Divider(height: 1),
              // 分类列表
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: moreGroups.length,
                  itemBuilder: (context, index) {
                    final group = moreGroups[index];
                    final isSelected = _selectedGroup == group;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedGroup = group;
                        });
                        _scrollToTop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF27ae60).withOpacity(0.1)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF27ae60)
                                    : themeService.isDarkMode
                                        ? const Color(0xFF2a2a2a)
                                        : const Color(0xFFf5f5f5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.category_outlined,
                                  size: 20,
                                  color: isSelected
                                      ? Colors.white
                                      : themeService.isDarkMode
                                          ? const Color(0xFF999999)
                                          : const Color(0xFF7f8c8d),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                group,
                                style: FontUtils.poppins(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFF27ae60)
                                      : themeService.isDarkMode
                                          ? Colors.white
                                          : const Color(0xFF2c3e50),
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF27ae60),
                                size: 24,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<LiveChannel> _getFilteredChannels() {
    if (_selectedGroup == '全部') {
      return _channelGroups.expand((g) => g.channels).toList();
    } else {
      return _channelGroups
          .firstWhere((g) => g.name == _selectedGroup,
              orElse: () => LiveChannelGroup(name: '', channels: []))
          .channels;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Column(
          children: [
            _buildTopBar(themeService),
            Expanded(
              child: _isLoading
                  ? _buildLoadingView(themeService)
                  : _errorMessage != null
                      ? _buildErrorView(themeService)
                      : _buildChannelList(themeService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(ThemeService themeService) {
    final visibleGroups = ['全部'];
    final moreGroups = _channelGroups.map((g) => g.name).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? const Color(0xFF1e1e1e).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                // 显示"全部"
                ...visibleGroups.map((group) {
                  final isSelected = _selectedGroup == group;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedGroup = group;
                      });
                      _scrollToTop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF27ae60)
                            : themeService.isDarkMode
                                ? const Color(0xFF2a2a2a)
                                : const Color(0xFFf5f5f5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        group,
                        style: FontUtils.poppins(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? Colors.white
                              : themeService.isDarkMode
                                  ? const Color(0xFFb0b0b0)
                                  : const Color(0xFF7f8c8d),
                        ),
                      ),
                    ),
                  );
                }),
                // 更多按钮
                if (moreGroups.isNotEmpty)
                  GestureDetector(
                    onTap: () =>
                        _showMoreGroupsBottomSheet(moreGroups, themeService),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: themeService.isDarkMode
                            ? const Color(0xFF2a2a2a)
                            : const Color(0xFFf5f5f5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: themeService.isDarkMode
                              ? const Color(0xFF333333)
                              : const Color(0xFFe0e0e0),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '更多',
                            style: FontUtils.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: themeService.isDarkMode
                                  ? const Color(0xFFb0b0b0)
                                  : const Color(0xFF7f8c8d),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: themeService.isDarkMode
                                ? const Color(0xFFb0b0b0)
                                : const Color(0xFF7f8c8d),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 当前源名称
          if (_currentSource != null)
            GestureDetector(
              onTap: () => _showSourceSwitchBottomSheet(themeService),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF3498DB).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.live_tv,
                      size: 16,
                      color: const Color(0xFF3498DB),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _currentSource!.name,
                      style: FontUtils.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF3498DB),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: const Color(0xFF3498DB),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 4),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF27ae60).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              color: const Color(0xFF27ae60),
              tooltip: '刷新直播源',
              onPressed: refreshChannels,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF27ae60)),
          ),
          const SizedBox(height: 16),
          Text(
            '加载中...',
            style: FontUtils.poppins(
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: themeService.isDarkMode
                ? const Color(0xFF666666)
                : const Color(0xFF95a5a6),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? '加载失败',
            style: FontUtils.poppins(
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: refreshChannels,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27ae60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '从 MoonTV 获取',
              style: FontUtils.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(ThemeService themeService) {
    final channels = _getFilteredChannels();

    if (channels.isEmpty) {
      return Center(
        child: Text(
          '暂无频道',
          style: FontUtils.poppins(
            color: themeService.isDarkMode
                ? const Color(0xFFb0b0b0)
                : const Color(0xFF7f8c8d),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        // 卡片长宽比为 2:1，加上标题高度约40，计算整体比例
        double childAspectRatio;

        if (constraints.maxWidth < 600) {
          crossAxisCount = 2;
          childAspectRatio = 1.5;
        } else if (constraints.maxWidth < 900) {
          crossAxisCount = 3;
          childAspectRatio = 1.5;
        } else if (constraints.maxWidth < 1200) {
          crossAxisCount = 4;
          childAspectRatio = 1.5;
        } else {
          crossAxisCount = 5;
          childAspectRatio = 1.5;
        }

        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            return _buildChannelCard(channels[index], themeService);
          },
        );
      },
    );
  }

  Widget _buildChannelCard(LiveChannel channel, ThemeService themeService) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LivePlayerScreen(
              channel: channel,
              source: _currentSource!,
            ),
          ),
        ).then((_) => _loadChannels());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 卡片主体 - 2:1 长宽比
          AspectRatio(
            aspectRatio: 2.0,
            child: Container(
              decoration: BoxDecoration(
                color: themeService.isDarkMode
                    ? const Color(0xFF1e1e1e)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: themeService.isDarkMode
                    ? null
                    : Border.all(
                        color: const Color(0xFFe1e8ed),
                        width: 1.5,
                      ),
                boxShadow: themeService.isDarkMode
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildChannelLogo(channel, themeService),
                  ),
                ],
              ),
            ),
          ),
          // 标题 - 放在卡片下方居中
          const SizedBox(height: 8),
          Text(
            channel.name,
            style: FontUtils.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: themeService.isDarkMode
                  ? Colors.white
                  : const Color(0xFF2c3e50),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelLogo(LiveChannel channel, ThemeService themeService) {
    // 如果有台标，显示台标
    if (channel.logo.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: themeService.isDarkMode
                ? [
                    const Color(0xFF2a2a2a),
                    const Color(0xFF1e1e1e),
                  ]
                : [
                    const Color(0xFFffffff),
                    const Color(0xFFf8f9fa),
                  ],
          ),
        ),
        child: Image.network(
          channel.logo,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultPreview(themeService);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildDefaultPreview(themeService);
          },
        ),
      );
    }
    // 没有台标，显示默认图标
    return _buildDefaultPreview(themeService);
  }

  Widget _buildDefaultPreview(ThemeService themeService) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: themeService.isDarkMode
              ? [
                  const Color(0xFF2a2a2a),
                  const Color(0xFF1e1e1e),
                ]
              : [
                  const Color(0xFFffffff),
                  const Color(0xFFf8f9fa),
                ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.tv,
          size: 48,
          color: themeService.isDarkMode
              ? const Color(0xFF666666)
              : const Color(0xFFadb5bd),
        ),
      ),
    );
  }
}
