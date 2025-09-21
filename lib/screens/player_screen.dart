import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/video_card.dart';
import '../services/api_service.dart';
import '../services/m3u8_service.dart';
import '../services/douban_service.dart';
import '../models/search_result.dart';
import '../models/douban_movie.dart';
import '../services/page_cache_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/image_url.dart';

class PlayerScreen extends StatefulWidget {
  final String? source;
  final String? id;
  final String title;
  final String? year;
  final String? stitle;
  final String? stype;
  final String? prefer;

  const PlayerScreen({
    super.key,
    this.source,
    this.id,
    required this.title,
    this.year,
    this.stitle,
    this.stype,
    this.prefer,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class SourceSpeed {
  String quality = '';
  String loadSpeed = '';
  String pingTime = '';

  SourceSpeed({
    required this.quality,
    required this.loadSpeed,
    required this.pingTime,
  });
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  late SystemUiOverlayStyle _originalStyle;
  bool _isInitialized = false;
  bool _isFullscreen = false;
  String? _errorMessage;
  bool _showError = false;

  // 播放信息
  SearchResult? currentDetail;
  String videoTitle = '';
  String videoDesc = '';
  String videoYear = '';
  String videoCover = '';
  int videoDoubanID = 0;
  String currentSource = '';
  String currentID = '';
  bool needPrefer = false;
  int totalEpisodes = 0;
  int currentEpisodeIndex = 0;
  
  // 豆瓣详情数据
  DoubanMovieDetails? doubanDetails;

  // 待恢复的进度
  double resumeTime = 0;
  
  // 所有源信息
  List<SearchResult> allSources = [];
  // 所有源测速结果
  Map<String, SourceSpeed> allSourcesSpeed = {};

  // 当前视频 URL
  String _currentVideoUrl = '';
  
  // VideoPlayerWidget 的控制器
  VideoPlayerWidgetController? _videoPlayerController;

  // 收藏状态
  bool _isFavorite = false;
  
  // 选集相关状态
  bool _isEpisodesReversed = false;
  final ScrollController _episodesScrollController = ScrollController();
  
  // 换源相关状态
  final ScrollController _sourcesScrollController = ScrollController();
  
  // 刷新相关状态
  bool _isRefreshing = false;
  late AnimationController _refreshAnimationController;

  @override
  void initState() {
    super.initState();
    _refreshAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    initVideoData();
  }

  void initParam() {
    currentSource = widget.source ?? '';
    currentID = widget.id ?? '';
    videoTitle = widget.title;
    videoYear = widget.year ?? '';
    needPrefer = widget.prefer != null && widget.prefer == 'true';

    print('=== PlayerScreen 初始化参数 ===');
    print('currentSource: $currentSource');
    print('currentID: $currentID');
    print('videoTitle: $videoTitle');
    print('videoYear: $videoYear');
    print('needPrefer: $needPrefer');
    print('stitle: ${widget.stitle}');
    print('stype: ${widget.stype}');
    print('prefer: ${widget.prefer}');
  }

  void initVideoData() async {
    if (widget.source == null && widget.id == null && widget.title.isEmpty && widget.stitle == null) {
      showError('缺少必要参数');
      return;
    }

    // 初始化参数
    initParam();
    
    // 执行查询
    allSources = await fetchSourcesData((widget.stitle != null && widget.stitle!.isNotEmpty) 
        ? widget.stitle! 
        : videoTitle);
    if (currentSource.isNotEmpty && currentID.isNotEmpty && !allSources.any((source) => source.source == currentSource && source.id == currentID)) {
      allSources = await fetchSourceDetail(currentSource, currentID);
    }
    if (allSources.isEmpty) {
      showError('未找到匹配的结果');
      return;
    }
    
    // 指定源和id且无需优选
    currentDetail = allSources.first;
    if (currentSource.isNotEmpty && currentID.isNotEmpty && !needPrefer) {
     final target = allSources.where((source) => source.source == currentSource && source.id == currentID);
     currentDetail = target.isNotEmpty ? target.first : null;
    }
    if (currentDetail == null) {
      showError('未找到匹配结果');
      return;
    }

    // 未指定源和 id/需要优选，执行优选
    if (currentSource.isEmpty || currentID.isEmpty || needPrefer) {
      currentDetail = await preferBestSource();
    }
    setInfosByDetail(currentDetail!);

    // 检查收藏状态
    _checkFavoriteStatus();

    // 获取播放记录
    int playEpisodeIndex = 0;
    int playTime = 0;
    final allPlayRecords = await PageCacheService().getPlayRecords(context);
    // 查找是否有当前视频的播放记录
    if (allPlayRecords.success && allPlayRecords.data != null) {
      final matchingRecords = allPlayRecords.data!.where((record) => record.id == currentID && record.source == currentSource);
      if (matchingRecords.isNotEmpty) {
        playEpisodeIndex = matchingRecords.first.index - 1;
        playTime = matchingRecords.first.playTime;
      }
    }

    // 设置播放
    startPlay(playEpisodeIndex, playTime);
  }

  void startPlay(int targetIndex, int playTime) {
    if (targetIndex >= currentDetail!.episodes.length) {
      targetIndex = 0;
      resumeTime = 0;
      return;
    }
    currentEpisodeIndex = targetIndex;
    resumeTime = playTime.toDouble();
    updateVideoUrl(currentDetail!.episodes[targetIndex]);
  }

  void setInfosByDetail(SearchResult detail) {
    videoTitle = detail.title;
    videoDesc = detail.desc ?? '';
    videoYear = detail.year;
    videoCover = detail.poster;
    currentSource = detail.source;
    currentID = detail.id;
    totalEpisodes = detail.episodes.length;

    // 保存旧的豆瓣ID用于比较
    int oldVideoDoubanID = videoDoubanID;

    // 设置当前豆瓣 ID
    if (detail.doubanId != null && detail.doubanId! > 0) {
      // 如果当前 searchResult 有有效的 doubanID，直接使用
      videoDoubanID = detail.doubanId!;
    } else {
      // 否则统计出现次数最多的 doubanID
      Map<int, int> doubanIDCount = {};
      for (var result in allSources) {
        int? tmpDoubanID = result.doubanId;
        if (tmpDoubanID == null || tmpDoubanID == 0) {
          continue;
        }
        doubanIDCount[tmpDoubanID] = (doubanIDCount[tmpDoubanID] ?? 0) + 1;
      }
      videoDoubanID = doubanIDCount.entries.isEmpty 
          ? 0 
          : doubanIDCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    }
    
    // 如果豆瓣ID发生变化且有效，获取豆瓣详情
    if (videoDoubanID != oldVideoDoubanID && videoDoubanID > 0) {
      _fetchDoubanDetails();
    }
    
    // 延迟调用自动滚动，确保UI已更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode();
      _scrollToCurrentSource();
    });
  }

  /// 获取豆瓣详情数据
  Future<void> _fetchDoubanDetails() async {
    if (videoDoubanID <= 0) {
      doubanDetails = null;
      return;
    }
    
    try {
      final response = await DoubanService.getDoubanDetails(
        context,
        doubanId: videoDoubanID.toString(),
      );
      
      if (response.success && response.data != null) {
        setState(() {
          doubanDetails = response.data;
          // 如果当前视频描述为空或是"暂无简介"，使用豆瓣的描述
          if ((videoDesc.isEmpty || videoDesc == '暂无简介') && response.data!.summary != null && response.data!.summary!.isNotEmpty) {
            videoDesc = response.data!.summary!;
          }
        });
      } else {
        print('获取豆瓣详情失败: ${response.message}');
      }
    } catch (e) {
      print('获取豆瓣详情异常: $e');
    }
  }

  Future<SearchResult> preferBestSource() async {
    final m3u8Service = M3U8Service();
    final result = await m3u8Service.preferBestSource(allSources);
    
    // 更新测速结果
    final speedResults = result['allSourcesSpeed'] as Map<String, dynamic>;
    for (final entry in speedResults.entries) {
      final speedData = entry.value as Map<String, dynamic>;
      allSourcesSpeed[entry.key] = SourceSpeed(
        quality: speedData['quality'] as String,
        loadSpeed: speedData['loadSpeed'] as String,
        pingTime: speedData['pingTime'] as String,
      );
    }
    
    return result['bestSource'] as SearchResult;
  }

  // 处理全屏状态变化（简化版本，只用于UI状态更新）
  void _handleFullscreenChange(bool isFullscreen) {
    if (_isFullscreen != isFullscreen) {
      setState(() {
        _isFullscreen = isFullscreen;
      });
    }
  }

  // 处理返回按钮点击
  void _onBackPressed() {
    Navigator.of(context).pop();
  }

  /// 显示错误信息
  void showError(String message) {
    setState(() {
      _errorMessage = message;
      _showError = true;
    });
  }

  /// 隐藏错误信息
  void hideError() {
    setState(() {
      _showError = false;
      _errorMessage = null;
    });
  }

  /// 动态更新视频 URL
  Future<void> updateVideoUrl(String newUrl) async {
    try {
      await _videoPlayerController?.updateVideoUrl(newUrl);
      setState(() {
        _currentVideoUrl = newUrl;
      });
    } catch (e) {
      showError('更新视频失败: $e');
    }
  }

  /// 跳转到指定进度
  Future<void> seekToProgress(Duration position) async {
    try {
      await _videoPlayerController?.seekTo(position);
    } catch (e) {
      showError('跳转进度失败: $e');
    }
  }

  /// 跳转到指定秒数
  Future<void> seekToSeconds(double seconds) async {
    await seekToProgress(Duration(seconds: seconds.round()));
  }

  /// 获取当前播放位置
  Duration? get currentPosition {
    return _videoPlayerController?.currentPosition;
  }

  /// 获取视频总时长
  Duration? get duration {
    return _videoPlayerController?.duration;
  }

  /// 获取播放状态
  bool get isPlaying {
    return _videoPlayerController?.isPlaying ?? false;
  }

  /// 处理视频播放器 ready 事件
  void _onVideoPlayerReady() {
    // 视频播放器准备就绪时的处理逻辑
    debugPrint('Video player is ready!');
    
    // 如果有需要恢复的播放进度，则跳转到指定位置
    if (resumeTime > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        seekToSeconds(resumeTime);
        resumeTime = 0;
      });
    }
  }

  /// 处理下一集按钮点击
  void _onNextEpisode() {
    if (currentDetail == null) return;
    
    // 检查是否为最后一集
    if (currentEpisodeIndex >= currentDetail!.episodes.length - 1) {
      _showToast('已经是最后一集了');
      return;
    }
    
    // 播放下一集
    final nextIndex = currentEpisodeIndex + 1;
    setState(() {
      currentEpisodeIndex = nextIndex;
    });
    updateVideoUrl(currentDetail!.episodes[nextIndex]);
    _scrollToCurrentEpisode();
  }

  /// 处理视频播放完成
  void _onVideoCompleted() {
    if (currentDetail == null) return;
    
    // 检查是否为最后一集
    if (currentEpisodeIndex >= currentDetail!.episodes.length - 1) {
      _showToast('播放完成');
      return;
    }
    
    // 自动播放下一集
    final nextIndex = currentEpisodeIndex + 1;
    setState(() {
      currentEpisodeIndex = nextIndex;
    });
    updateVideoUrl(currentDetail!.episodes[nextIndex]);
    _scrollToCurrentEpisode();
  }

  /// 显示Toast消息
  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// 检查收藏状态
  void _checkFavoriteStatus() {
    if (currentSource.isNotEmpty && currentID.isNotEmpty) {
      final cacheService = PageCacheService();
      final isFavorited = cacheService.isFavoritedSync(currentSource, currentID);
      setState(() {
        _isFavorite = isFavorited;
      });
    }
  }

  /// 切换收藏状态
  void _toggleFavorite() async {
    if (currentSource.isEmpty || currentID.isEmpty) return;
    
    final cacheService = PageCacheService();
    
    if (_isFavorite) {
      // 取消收藏
      final result = await cacheService.removeFavorite(currentSource, currentID, context);
      if (result.success) {
        setState(() {
          _isFavorite = false;
        });
      }
    } else {
      // 添加收藏
      final favoriteData = {
        'cover': videoCover,
        'save_time': DateTime.now().millisecondsSinceEpoch,
        'source_name': currentDetail?.sourceName ?? '',
        'title': videoTitle,
        'total_episodes': totalEpisodes,
        'year': videoYear,
      };
      
      final result = await cacheService.addFavorite(currentSource, currentID, favoriteData, context);
      if (result.success) {
        setState(() {
          _isFavorite = true;
        });
      }
    }
  }

  /// 切换选集排序
  void _toggleEpisodesOrder() {
    setState(() {
      _isEpisodesReversed = !_isEpisodesReversed;
    });
    // 切换排序后自动滚动到当前集数
    _scrollToCurrentEpisode();
  }


  /// 滚动到当前源
  void _scrollToCurrentSource() {
    if (currentDetail == null) return;
    
    // 换源已收起，直接执行滚动
    _performScrollToCurrentSource();
  }

  /// 执行滚动到当前源的具体逻辑
  void _performScrollToCurrentSource() {
    if (currentDetail == null || !_sourcesScrollController.hasClients) return;
    
    // 找到当前源在allSources中的索引
    final currentSourceIndex = allSources.indexWhere(
      (source) => source.source == currentSource && source.id == currentID
    );
    
    if (currentSourceIndex == -1) return;
    
    // 动态计算卡片宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = 32.0;
    final availableWidth = screenWidth - horizontalPadding;
    final cardWidth = (availableWidth / 3.2) - 6;
    final itemWidth = cardWidth + 6; // 卡片宽度 + 右边距
    
    // 计算选中项在屏幕中央的偏移量
    final centerOffset = (screenWidth - horizontalPadding) / 2 - cardWidth / 2;
    final targetOffset = (currentSourceIndex * itemWidth) - centerOffset;
    
    // 确保不滚动到负值或超出范围
    final maxScrollExtent = _sourcesScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent);
    
    _sourcesScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 切换视频源
  void _switchSource(SearchResult newSource) {
    // 保存当前播放进度
    final currentProgress = currentPosition?.inSeconds ?? 0;
    final currentEpisode = currentEpisodeIndex;
    
    setState(() {
      currentDetail = newSource;
      currentSource = newSource.source;
      currentID = newSource.id;
      currentEpisodeIndex = currentEpisode; // 保持当前集数
      totalEpisodes = newSource.episodes.length;
      _isEpisodesReversed = false;
    });
    
    // 更新视频信息
    setInfosByDetail(newSource);
    
    // 重新检查收藏状态（因为源和ID可能已改变）
    _checkFavoriteStatus();
    
    // 开始播放新源，使用当前播放器的进度
    startPlay(currentEpisode, currentProgress);
    
    // 延迟滚动到当前源，等待UI更新完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSource();
    });
  }

  /// 自动滚动到当前集数
  void _scrollToCurrentEpisode() {
    if (currentDetail == null) return;
    
    // 如果选集展开，先收起选集，然后滚动到当前集数
    _performScrollToCurrentEpisode();
  }

  /// 执行滚动到当前集数的具体逻辑
  void _performScrollToCurrentEpisode() {
    if (currentDetail == null || !_episodesScrollController.hasClients) return;
    
    // 动态计算按钮宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = 32.0;
    final availableWidth = screenWidth - horizontalPadding;
    final buttonWidth = (availableWidth / 3.2) - 6;
    final itemWidth = buttonWidth + 6; // 按钮宽度 + 右边距
    
    final targetIndex = _isEpisodesReversed 
        ? currentDetail!.episodes.length - 1 - currentEpisodeIndex 
        : currentEpisodeIndex;
    
    // 计算选中项在屏幕中央的偏移量
    // 屏幕宽度的一半减去按钮宽度的一半，让选中项居中
    final centerOffset = (screenWidth - horizontalPadding) / 2 - buttonWidth / 2;
    final targetOffset = (targetIndex * itemWidth) - centerOffset;
    
    // 确保不滚动到负值或超出范围
    final maxScrollExtent = _episodesScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScrollExtent);
    
    _episodesScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 构建视频详情展示区域
  Widget _buildVideoDetailSection(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    if (currentDetail == null) {
      return Container(
        color: Colors.transparent,
        child: const Center(
          child: Text('加载中...'),
        ),
      );
    }
    
    return Container(
      color: Colors.transparent,
      child: SingleChildScrollView(
        child: Column(
          children: [
          // 标题和收藏按钮行
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    videoTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF2c3e50),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _toggleFavorite,
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? const Color(0xFFe74c3c) : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          
          // 源名称、年份和分类信息行
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 16, top: 12, bottom: 16),
            child: Row(
              children: [
                // 源名称（带边框样式）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    currentDetail!.sourceName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDarkMode ? Colors.grey[300] : Colors.black87,
                    ),
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // 年份
                if (videoYear.isNotEmpty)
                  Text(
                    videoYear,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDarkMode ? Colors.grey[300] : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                
                if (videoYear.isNotEmpty)
                  const SizedBox(width: 12),
                
                // 分类信息（绿色文字样式）
                if (currentDetail!.class_ != null && currentDetail!.class_!.isNotEmpty)
                  Text(
                    currentDetail!.class_!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF2ecc71),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                
                const Spacer(),
                
                // 详情按钮
                GestureDetector(
                  onTap: () {
                    // TODO: 实现详情页面跳转
                    _showDetailsPanel();
                  },
                  child: Stack(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '详情',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(width: 18),
                        ],
                      ),
                      Positioned(
                        right: 0,
                        top: 4,
                        child: Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 视频描述行
          if (videoDesc.isNotEmpty || (doubanDetails?.summary != null && doubanDetails!.summary!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  (videoDesc.isNotEmpty && videoDesc != '暂无简介') ? videoDesc : (doubanDetails?.summary ?? '暂无简介'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          
          // 选集区域
          _buildEpisodesSection(theme),
          
          const SizedBox(height: 16),

          // 换源区域
          _buildSourcesSection(theme),
          
          const SizedBox(height: 16),
          
          // 相关推荐区域
          _buildRecommendsSection(theme),
        ],
        ),
      ),
    );
  }

  /// 构建相关推荐区域
  Widget _buildRecommendsSection(ThemeData theme) {
    // 如果没有豆瓣详情或推荐列表为空，不显示此区域
    if (doubanDetails == null || doubanDetails!.recommends.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: [
        // 推荐标题行
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '相关推荐',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        
        // 推荐卡片网格
        Transform.translate(
          offset: const Offset(0, -8),
          child: _buildRecommendsGrid(theme),
        ),
      ],
    );
  }

  /// 构建推荐卡片网格
  Widget _buildRecommendsGrid(ThemeData theme) {
    final recommends = doubanDetails!.recommends;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final double screenWidth = constraints.maxWidth;
        final double padding = 16.0;
        final double spacing = 12.0;
        final double availableWidth = screenWidth - (padding * 2) - (spacing * 2);
        final double minItemWidth = 80.0;
        final double calculatedItemWidth = availableWidth / 3;
        final double itemWidth = math.max(calculatedItemWidth, minItemWidth);
        final double itemHeight = itemWidth * 2.0;
        
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: itemWidth / itemHeight,
              crossAxisSpacing: spacing,
              mainAxisSpacing: 4,
            ),
            itemCount: recommends.length,
            itemBuilder: (context, index) {
              final recommend = recommends[index];
              final videoInfo = recommend.toVideoInfo();
              
              return VideoCard(
                videoInfo: videoInfo,
                from: 'douban',
                cardWidth: itemWidth,
                onTap: () => _onRecommendTap(recommend),
              );
            },
          ),
        );
      },
    );
  }

  /// 处理推荐卡片点击
  void _onRecommendTap(DoubanRecommendItem recommend) {
    // 如果当前正在播放，则暂停播放
    if (_videoPlayerController?.isPlaying == true) {
      _videoPlayerController?.pause();
    }
    
    // 跳转到新的播放页，只传递title参数
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          title: recommend.title,
        ),
      ),
    );
  }

  /// 构建选集区域
  Widget _buildEpisodesSection(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // 选集标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '选集',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              
              // 正序/倒序按钮
              GestureDetector(
                onTap: _toggleEpisodesOrder,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _isEpisodesReversed ? '倒序' : '正序',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Transform.translate(
                      offset: const Offset(0, 3),
                      child: Icon(
                        _isEpisodesReversed ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // 滚动到当前集数按钮
              Transform.translate(
                offset: const Offset(0, 3.5),
                child: GestureDetector(
                  onTap: _scrollToCurrentEpisode,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDarkMode ? Colors.grey[400]! : Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 20),
              
              // 展开按钮
              GestureDetector(
                onTap: _showEpisodesPanel,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -1.2),
                      child: Text(
                        '展开',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 2),

        // 集数卡片横向滚动区域
        LayoutBuilder(
          builder: (context, constraints) {
            // 计算按钮宽度：屏幕宽度减去左右padding，除以3.2，再减去间距
            final screenWidth = constraints.maxWidth;
            final horizontalPadding = 32.0; // 左右各16
            final availableWidth = screenWidth - horizontalPadding;
            final buttonWidth = (availableWidth / 3.2) - 6; // 减去右边距6
            final buttonHeight = buttonWidth * 1.8 / 3; // 稍微减少高度
            
            return SizedBox(
              height: buttonHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.builder(
                  controller: _episodesScrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: currentDetail!.episodes.length,
                  itemBuilder: (context, index) {
                    final episodeIndex = _isEpisodesReversed 
                        ? currentDetail!.episodes.length - 1 - index 
                        : index;
                    final episode = currentDetail!.episodes[episodeIndex];
                    final isCurrentEpisode = episodeIndex == currentEpisodeIndex;
                    
                    // 获取集数名称，如果episodesTitles为空或长度不够，则使用默认格式
                    String episodeTitle = '';
                    if (currentDetail!.episodesTitles.isNotEmpty && 
                        episodeIndex < currentDetail!.episodesTitles.length) {
                      episodeTitle = currentDetail!.episodesTitles[episodeIndex];
                    } else {
                      episodeTitle = '第${episodeIndex + 1}集';
                    }
                    
                    return Container(
                      width: buttonWidth,
                      margin: const EdgeInsets.only(right: 6),
                      child: AspectRatio(
                        aspectRatio: 3 / 2, // 严格保持3:2宽高比
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              currentEpisodeIndex = episodeIndex;
                            });
                            updateVideoUrl(episode);
                            _scrollToCurrentEpisode();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isCurrentEpisode 
                                  ? Colors.green.withOpacity(0.2) 
                                  : (isDarkMode ? Colors.grey[700] : Colors.grey[300]),
                              borderRadius: BorderRadius.circular(8),
                              border: isCurrentEpisode 
                                  ? Border.all(color: Colors.green, width: 2)
                                  : null,
                            ),
                            child: Stack(
                              children: [
                                // 左上角集数
                                Positioned(
                                  top: 4,
                                  left: 6,
                                  child: Text(
                                    '${episodeIndex + 1}',
                                    style: TextStyle(
                                      color: isCurrentEpisode ? Colors.green : (isDarkMode ? Colors.white : Colors.black),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                                // 中间集数名称
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                                    child: Text(
                                      episodeTitle,
                                      style: TextStyle(
                                        color: isCurrentEpisode ? Colors.green : (isDarkMode ? Colors.white : Colors.black),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 构建选集底部滑出面板
  void _showEpisodesPanel() {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final playerHeight = screenWidth / (16 / 9);
    final panelHeight = screenHeight - statusBarHeight - playerHeight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SizedBox(
              height: panelHeight,
              child: _EpisodesGridPanel(
                theme: theme,
                episodes: currentDetail!.episodes,
                episodesTitles: currentDetail!.episodesTitles,
                currentEpisodeIndex: currentEpisodeIndex,
                isReversed: _isEpisodesReversed,
                onEpisodeTap: (index) {
                  this.setState(() {
                    currentEpisodeIndex = index;
                  });
                  updateVideoUrl(currentDetail!.episodes[index]);
                  Navigator.pop(context);
                  _scrollToCurrentEpisode();
                },
                onToggleOrder: () {
                  setState(() {
                    _isEpisodesReversed = !_isEpisodesReversed;
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  /// 构建详情底部滑出面板
  void _showDetailsPanel() {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final playerHeight = screenWidth / (16 / 9);
    final panelHeight = screenHeight - statusBarHeight - playerHeight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SizedBox(
              height: panelHeight,
              child: _DetailsPanel(
                theme: theme,
                doubanDetails: doubanDetails,
                currentDetail: currentDetail,
              ),
            );
          },
        );
      },
    );
  }

  /// 构建换源区域
  Widget _buildSourcesSection(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // 换源标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '换源',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const Spacer(),
              
              // 刷新按钮
              Transform.translate(
                offset: const Offset(0, 2.6),
                child: GestureDetector(
                  onTap: _isRefreshing ? null : _refreshSourcesSpeed,
                  child: RotationTransition(
                    turns: _refreshAnimationController,
                    child: Icon(
                      Icons.refresh,
                      size: 20,
                      color: _isRefreshing ? Colors.green : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 20),
              
              // 滚动到当前源按钮
              Transform.translate(
                offset: const Offset(0, 3.5),
                child: GestureDetector(
                  onTap: _scrollToCurrentSource,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDarkMode ? Colors.grey[400]! : Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 20),
              
              // 展开按钮
              GestureDetector(
                onTap: _showSourcesPanel,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -1.2),
                      child: Text(
                        '展开',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 2),

        // 源卡片横向滚动区域
        _buildSourcesHorizontalScroll(theme),
      ],
    );
  }

  /// 构建源卡片横向滚动区域
  Widget _buildSourcesHorizontalScroll(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算卡片宽度：屏幕宽度减去左右padding，除以3.2，再减去间距
        final screenWidth = constraints.maxWidth;
        final horizontalPadding = 32.0; // 左右各16
        final availableWidth = screenWidth - horizontalPadding;
        final cardWidth = (availableWidth / 3.2) - 6; // 减去右边距6
        final cardHeight = cardWidth * 1.8 / 3; // 稍微减少高度
        
        return SizedBox(
          height: cardHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              controller: _sourcesScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: allSources.length,
              itemBuilder: (context, index) {
                final source = allSources[index];
                final isCurrentSource = source.source == currentSource && source.id == currentID;
                final sourceKey = '${source.source}_${source.id}';
                final speedInfo = allSourcesSpeed[sourceKey];
                
                return Container(
                  width: cardWidth,
                  margin: const EdgeInsets.only(right: 6),
                  child: AspectRatio(
                    aspectRatio: 3 / 2, // 严格保持3:2宽高比
                    child: GestureDetector(
                      onTap: isCurrentSource ? null : () => _switchSource(source),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrentSource 
                              ? Colors.green.withOpacity(0.2) 
                              : (isDarkMode ? Colors.grey[700] : Colors.grey[300]),
                          borderRadius: BorderRadius.circular(8),
                          border: isCurrentSource 
                              ? Border.all(color: Colors.green, width: 2)
                              : null,
                        ),
                        child: Stack(
                          children: [
                            // 右上角集数信息
                            Positioned(
                              top: 4,
                              right: 6,
                              child: Text(
                                '${source.episodes.length}集',
                                style: TextStyle(
                                  color: isCurrentSource ? Colors.green : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            
                            // 中间源名称
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  source.sourceName,
                                  style: TextStyle(
                                    color: isCurrentSource ? Colors.green : (isDarkMode ? Colors.white : Colors.black),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            
                            // 左下角分辨率信息
                            if (speedInfo != null && speedInfo.quality.toLowerCase() != '未知')
                              Positioned(
                                bottom: 4,
                                left: 6,
                                child: Text(
                                  speedInfo.quality,
                                  style: TextStyle(
                                    color: isCurrentSource ? Colors.green : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            
                            // 右下角速率信息
                            if (speedInfo != null && speedInfo.loadSpeed.isNotEmpty && !speedInfo.loadSpeed.toLowerCase().contains('超时'))
                              Positioned(
                                bottom: 4,
                                right: 6,
                                child: Text(
                                  speedInfo.loadSpeed,
                                  style: TextStyle(
                                    color: isCurrentSource ? Colors.green : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }


  /// 构建换源列表
  void _showSourcesPanel() {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final playerHeight = screenWidth / (16 / 9);
    final panelHeight = screenHeight - statusBarHeight - playerHeight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SizedBox(
              height: panelHeight,
              child: _SourcesGridPanel(
                theme: theme,
                sources: allSources,
                currentSource: currentSource,
                currentId: currentID,
                sourcesSpeed: allSourcesSpeed,
                onSourceTap: (source) {
                  this.setState(() {
                    _switchSource(source);
                  });
                  Navigator.pop(context);
                },
                onRefresh: () async {
                  await _refreshSourcesSpeed(setState);
                },
                videoCover: videoCover,
                videoTitle: videoTitle,
              ),
            );
          },
        );
      },
    );
  }

  /// 刷新所有源的测速结果
  Future<void> _refreshSourcesSpeed([StateSetter? stateSetter]) async {
    if (allSources.isEmpty) return;
    
    final aSetState = stateSetter ?? setState;
    
    // 如果是从外部调用（非面板），设置刷新状态
    if (stateSetter == null) {
      setState(() {
        _isRefreshing = true;
      });
      _refreshAnimationController.repeat();
    }

    try {
      // 清空之前的测速结果
      allSourcesSpeed.clear();
      
      // 立即更新UI显示，让用户看到测速信息被清空
      aSetState(() {});
      
      // 使用新的实时测速方法
      final m3u8Service = M3U8Service();
      await m3u8Service.testSourcesWithCallback(
        allSources,
        (String sourceId, Map<String, dynamic> speedData) {
          // 每个源测速完成后立即更新
          allSourcesSpeed[sourceId] = SourceSpeed(
            quality: speedData['quality'] as String,
            loadSpeed: speedData['loadSpeed'] as String,
            pingTime: speedData['pingTime'] as String,
          );
          
          // 立即更新UI显示
          aSetState(() {});
        },
        timeout: const Duration(seconds: 10), // 自定义超时时间
      );
      
    } catch (e) {
      showError('刷新测速失败: $e');
    } finally {
      // 如果是从外部调用（非面板），停止刷新状态
      if (stateSetter == null) {
        setState(() {
          _isRefreshing = false;
        });
        _refreshAnimationController.stop();
        _refreshAnimationController.reset();
      }
    }
  }


  /// 构建错误覆盖层
  Widget _buildErrorOverlay(ThemeData theme) {
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: isDarkMode 
          ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.grey],
            )
          : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFe6f3fb), // 与首页保持一致
                Color(0xFFeaf3f7),
                Color(0xFFf7f7f3),
                Color(0xFFe9ecef),
                Color(0xFFdbe3ea),
                Color(0xFFd3dde6),
              ],
              stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
            ),
      ),
      child: Stack(
        children: [
          // 装饰性圆点
          Positioned(
            top: 100,
            left: 40,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 140,
            left: 60,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 120,
            right: 50,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          // 主要内容
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 错误图标
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFF8C42), Color(0xFFE74C3C)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '😵',
                      style: TextStyle(fontSize: 60),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // 错误标题
                Text(
                  '哎呀, 出现了一些问题',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                
                // 错误信息框
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B4513).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8B4513).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFFE74C3C),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                
                // 提示文字
                Text(
                  '请检查网络连接或尝试刷新页面',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                
                // 按钮组
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      // 返回按钮
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            hideError();
                            _onBackPressed();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                          ),
                          child: const Text(
                            '返回上页',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // 重试按钮
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: hideError,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDarkMode ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0),
                            foregroundColor: isDarkMode ? Colors.white : const Color(0xFF3182CE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                          ),
                          child: Text(
                            '重新尝试',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? Colors.white : const Color(0xFF3182CE),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  /// 获取视频详情
  Future<List<SearchResult>> fetchSourceDetail(String source, String id) async {
    return await ApiService.fetchSourceDetail(source, id);
  }

  /// 搜索视频源数据（带过滤）
  Future<List<SearchResult>> fetchSourcesData(String query) async {
    final results = await ApiService.fetchSourcesData(query);
    
    // 直接在这里展开过滤逻辑
    return results.where((result) {
      // 标题匹配检查
      final titleMatch = result.title.replaceAll(' ', '').toLowerCase() == 
          (widget.title.replaceAll(' ', '').toLowerCase());
      
      // 年份匹配检查
      final yearMatch = widget.year == null || 
          result.year.toLowerCase() == widget.year!.toLowerCase();
      
      // 类型匹配检查
      bool typeMatch = true;
      if (widget.stype != null) {
        if (widget.stype == 'tv') {
          typeMatch = result.episodes.length > 1;
        } else if (widget.stype == 'movie') {
          typeMatch = result.episodes.length == 1;
        }
      }
      
      return titleMatch && yearMatch && typeMatch;
    }).toList();
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      // 保存当前的系统UI样式
      final theme = Theme.of(context);
      final isDarkMode = theme.brightness == Brightness.dark;
      _originalStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
      );
      _isInitialized = true;
    }
  }


  @override
  void dispose() {
    // 恢复原始的系统UI样式
    SystemChrome.setSystemUIOverlayStyle(_originalStyle);
    // 销毁播放器
    _videoPlayerController?.dispose();
    // 释放滚动控制器
    _episodesScrollController.dispose();
    _sourcesScrollController.dispose();
    // 释放动画控制器
    _refreshAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: isDarkMode ? Colors.black : theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        // 其余代码保持不变
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: isDarkMode 
                ? null
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFe6f3fb), // 与首页保持一致的浅色模式渐变
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
            // 主要内容
            Column(
              children: [
                Container(
                  height: MediaQuery.maybeOf(context)?.padding.top ?? 0,
                  color: Colors.black,
                ),
                VideoPlayerWidget(
                  videoUrl: _currentVideoUrl,
                  aspectRatio: 16 / 9,
                  onBackPressed: _onBackPressed,
                  onFullscreenChange: _handleFullscreenChange,
                  onControllerCreated: (controller) {
                    _videoPlayerController = controller;
                  },
                  onReady: _onVideoPlayerReady,
                  onNextEpisode: _onNextEpisode,
                  onVideoCompleted: _onVideoCompleted,
                ),
                Expanded(
                  child: _buildVideoDetailSection(theme),
                ),
              ],
            ),
            // 错误覆盖层
            if (_showError && _errorMessage != null)
              _buildErrorOverlay(theme),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  final ThemeData theme;
  final DoubanMovieDetails? doubanDetails;
  final SearchResult? currentDetail;

  const _DetailsPanel({
    required this.theme,
    this.doubanDetails,
    this.currentDetail,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1c1c1e) : Colors.white,
      ),
      child: Column(
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '详情',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            // child: _buildCurrentDetailPanel(isDarkMode),
            child: doubanDetails != null 
                ? _buildDoubanDetailsPanel(isDarkMode)
                : _buildCurrentDetailPanel(isDarkMode),
          ),
        ],
      ),
    );
  }

  /// 构建豆瓣详情面板
  Widget _buildDoubanDetailsPanel(bool isDarkMode) {
    final String title = doubanDetails!.title;
    final String cover = doubanDetails!.poster;
    final String year = doubanDetails!.year;
    final String? rate = doubanDetails!.rate;
    final List<String> genres = doubanDetails!.genres;
    final List<String> directors = doubanDetails!.directors;
    final List<String> writers = doubanDetails!.screenwriters;
    final List<String> actors = doubanDetails!.actors;
    final String summary = doubanDetails!.summary ?? '暂无简介';
    final List<String> countries = doubanDetails!.countries;
    final List<String> languages = doubanDetails!.languages;
    final String? duration = doubanDetails!.duration;
    final String? originalTitle = doubanDetails!.originalTitle;
    final String? releaseDate = doubanDetails!.releaseDate;
    final int? totalEpisodes = doubanDetails!.totalEpisodes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主要信息区域
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧封面
              SizedBox(
                width: 120,
                height: 160,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: cover.isNotEmpty
                          ? FutureBuilder<String>(
                              future: getImageUrl(cover, 'douban'),
                              builder: (context, snapshot) {
                                final String imageUrl = snapshot.data ?? cover;
                                final headers = getImageRequestHeaders(imageUrl, 'douban');
                                
                                return CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  width: 120,
                                  height: 160,
                                  cacheKey: imageUrl,
                                  httpHeaders: headers,
                                  memCacheWidth: (120 * MediaQuery.of(context).devicePixelRatio).round(),
                                  memCacheHeight: (160 * MediaQuery.of(context).devicePixelRatio).round(),
                                  placeholder: (context, url) => Container(
                                    width: 120,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: 120,
                                    height: 160,
                                    color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                    child: const Icon(Icons.movie, size: 50),
                                  ),
                                  fadeInDuration: const Duration(milliseconds: 200),
                                  fadeOutDuration: const Duration(milliseconds: 100),
                                );
                              },
                            )
                          : Container(
                              width: 120,
                              height: 160,
                              color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                              child: const Icon(Icons.movie, size: 50),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 右侧信息
              Expanded(
                child: SizedBox(
                  height: 160, // 固定高度与封面图一致
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // 标题
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 原标题（如果存在且与标题不同）
                      if (originalTitle != null && originalTitle.isNotEmpty && originalTitle != title)
                        Text(
                          originalTitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      // 底部信息区域
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 地区和语言
                          if (countries.isNotEmpty || languages.isNotEmpty)
                            Text(
                              [
                                if (countries.isNotEmpty) countries.join(' | '),
                                if (languages.isNotEmpty) languages.join(' | '),
                              ].join(' | '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          const SizedBox(height: 4),
                          // 年份
                          Text(
                            year,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 时长
                          if (duration != null && duration.isNotEmpty)
                            Text(
                              duration,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          if (duration != null && duration.isNotEmpty)
                            const SizedBox(height: 4),
                          // 总集数
                          if (totalEpisodes != null && totalEpisodes > 1)
                            Text(
                              '全${totalEpisodes}集',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          if (totalEpisodes != null && totalEpisodes > 1)
                            const SizedBox(height: 4),
                          // 首映首播日期
                          if (releaseDate != null)
                            Text(
                              releaseDate,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 评分
              if (rate != null && rate.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      rate,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildStarRating(rate, isDarkMode),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 标签区域
          if (genres.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '风格',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: genres.map((genre) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      genre,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // 制作信息
          if (directors.isNotEmpty || writers.isNotEmpty || actors.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '制作信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                _buildProductionInfo(directors, writers, actors, isDarkMode),
              ],
            ),
          const SizedBox(height: 16),
          // 简介
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '简介',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建当前详情面板（基于currentDetail）
  Widget _buildCurrentDetailPanel(bool isDarkMode) {
    final String title = currentDetail?.title ?? '暂无标题';
    final String cover = currentDetail?.poster ?? '';
    final String year = currentDetail?.year ?? '未知年份';
    final String summary = currentDetail?.desc ?? '暂无简介';
    final String? sourceName = currentDetail?.sourceName;
    final String? class_ = currentDetail?.class_;
    final List<String> episodes = currentDetail?.episodes ?? [];
    final int totalEpisodes = episodes.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主要信息区域
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧封面
              SizedBox(
                width: 120,
                height: 160,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: cover.isNotEmpty
                          ? FutureBuilder<String>(
                              future: getImageUrl(cover, currentDetail?.source),
                              builder: (context, snapshot) {
                                final String imageUrl = snapshot.data ?? cover;
                                final headers = getImageRequestHeaders(imageUrl, currentDetail?.source);
                                
                                return CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  width: 120,
                                  height: 160,
                                  cacheKey: imageUrl,
                                  httpHeaders: headers,
                                  memCacheWidth: (120 * MediaQuery.of(context).devicePixelRatio).round(),
                                  memCacheHeight: (160 * MediaQuery.of(context).devicePixelRatio).round(),
                                  placeholder: (context, url) => Container(
                                    width: 120,
                                    height: 160,
                                    decoration: BoxDecoration(
                                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    width: 120,
                                    height: 160,
                                    color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                    child: const Icon(Icons.movie, size: 50),
                                  ),
                                  fadeInDuration: const Duration(milliseconds: 200),
                                  fadeOutDuration: const Duration(milliseconds: 100),
                                );
                              },
                            )
                          : Container(
                              width: 120,
                              height: 160,
                              color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                              child: const Icon(Icons.movie, size: 50),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // 右侧信息
              Expanded(
                child: SizedBox(
                  height: 160, // 固定高度与封面图一致
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // 标题
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // 底部信息区域
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 源名称
                          if (sourceName != null && sourceName.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                border: Border.all(color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sourceName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                                ),
                              ),
                            ),
                          if (sourceName != null && sourceName.isNotEmpty)
                            const SizedBox(height: 4),
                          // 年份
                          Text(
                            year,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 总集数
                          if (totalEpisodes > 1)
                            Text(
                              '全${totalEpisodes}集',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 分类信息
          if (class_ != null && class_.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '分类',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: class_.split(',').map((category) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      category.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // 简介
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '简介',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStarRating(String rate, bool isDarkMode) {
    try {
      final rating = double.parse(rate);
      // 将10分制转换为5分制：除以2
      final double fiveStarRating = rating / 2.0;
      final int fullStars = fiveStarRating.floor();
      final bool hasHalfStar = (fiveStarRating - fullStars) >= 0.5;
      
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          if (index < fullStars) {
            // 完整星星
            return Icon(
              Icons.star,
              color: Colors.orange,
              size: 16,
            );
          } else if (index == fullStars && hasHalfStar) {
            // 半星
            return Icon(
              Icons.star_half,
              color: Colors.grey[400],
              size: 16,
            );
          } else {
            // 空星
            return Icon(
              Icons.star,
              color: Colors.grey[400],
              size: 16,
            );
          }
        }),
      );
    } catch (e) {
      // 如果解析失败，显示5颗空星
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) => Icon(
          Icons.star,
          color: Colors.grey[400],
          size: 16,
        )),
      );
    }
  }


  Widget _buildProductionInfo(List<String> directors, List<String> writers, List<String> actors, bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (directors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                children: [
                  TextSpan(text: '导演: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: directors.join(' / ')),
                ],
              ),
            ),
          ),
        if (writers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                children: [
                  TextSpan(text: '编剧: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: writers.join(' / ')),
                ],
              ),
            ),
          ),
        if (actors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
                children: [
                  TextSpan(text: '主演: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: actors.join(' / ')),
                ],
              ),
            ),
          ),
      ],
    );
  }

}

class _EpisodesGridPanel extends StatefulWidget {
  final ThemeData theme;
  final List<String> episodes;
  final List<String> episodesTitles;
  final int currentEpisodeIndex;
  final bool isReversed;
  final Function(int) onEpisodeTap;
  final VoidCallback onToggleOrder;

  const _EpisodesGridPanel({
    required this.theme,
    required this.episodes,
    required this.episodesTitles,
    required this.currentEpisodeIndex,
    required this.isReversed,
    required this.onEpisodeTap,
    required this.onToggleOrder,
  });

  @override
  State<_EpisodesGridPanel> createState() => _EpisodesGridPanelState();
}

class _EpisodesGridPanelState extends State<_EpisodesGridPanel> {
  final GlobalKey _gridKey = GlobalKey();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToCurrent();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (_gridKey.currentContext == null) return;

    final gridBox = _gridKey.currentContext!.findRenderObject() as RenderBox;

    final targetIndex = widget.isReversed
        ? widget.episodes.length - 1 - widget.currentEpisodeIndex
        : widget.currentEpisodeIndex;
    
    const crossAxisCount = 2;
    const mainAxisSpacing = 12.0;
    const childAspectRatio = 3.0;
    
    final itemWidth = (gridBox.size.width - (crossAxisCount - 1) * 12) / crossAxisCount;
    final itemHeight = itemWidth / childAspectRatio;

    final row = (targetIndex / crossAxisCount).floor();
    final offset = row * (itemHeight + mainAxisSpacing);

    _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1c1c1e) : Colors.white,
      ),
      child: Column(
        children: [
          // 标题和关闭按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '选集 (${widget.episodes.length})',
                  style: widget.theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // 集数网格
          Expanded(
            child: GridView.builder(
              key: _gridKey,
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 3.0,
              ),
              itemCount: widget.episodes.length,
              itemBuilder: (context, index) {
                final episodeIndex = widget.isReversed
                    ? widget.episodes.length - 1 - index
                    : index;
                final isCurrentEpisode = episodeIndex == widget.currentEpisodeIndex;
                
                String episodeTitle = '';
                if (widget.episodesTitles.isNotEmpty && episodeIndex < widget.episodesTitles.length) {
                  episodeTitle = widget.episodesTitles[episodeIndex];
                } else {
                  episodeTitle = '第${episodeIndex + 1}集';
                }
                
                return GestureDetector(
                  onTap: () => widget.onEpisodeTap(episodeIndex),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrentEpisode
                          ? Colors.green.withOpacity(0.2)
                          : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(8),
                      border: isCurrentEpisode
                          ? Border.all(color: Colors.green, width: 2)
                          : null,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 4,
                          left: 6,
                          child: Text(
                            '${episodeIndex + 1}',
                            style: TextStyle(
                              color: isCurrentEpisode
                                  ? Colors.green
                                  : (isDarkMode ? Colors.white70 : Colors.black87),
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              episodeTitle,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrentEpisode
                                    ? Colors.green
                                    : (isDarkMode ? Colors.white : Colors.black),
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcesGridPanel extends StatefulWidget {
  final ThemeData theme;
  final List<SearchResult> sources;
  final String currentSource;
  final String currentId;
  final Map<String, SourceSpeed> sourcesSpeed;
  final Function(SearchResult) onSourceTap;
  final Future<void> Function() onRefresh;
  final String videoCover;
  final String videoTitle;

  const _SourcesGridPanel({
    required this.theme,
    required this.sources,
    required this.currentSource,
    required this.currentId,
    required this.sourcesSpeed,
    required this.onSourceTap,
    required this.onRefresh,
    required this.videoCover,
    required this.videoTitle,
  });

  @override
  State<_SourcesGridPanel> createState() => _SourcesGridPanelState();
}

class _SourcesGridPanelState extends State<_SourcesGridPanel> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _isRefreshing = false;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scrollController = ScrollController();
    
    // 延迟滚动到当前源
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSource();
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startRefreshAnimation() {
    _rotationController.repeat();
  }

  void _stopRefreshAnimation() {
    _rotationController.stop();
    _rotationController.reset();
  }

  void _scrollToCurrentSource() {
    if (!_scrollController.hasClients) return;
    
    // 找到当前源在列表中的索引
    final currentIndex = widget.sources.indexWhere(
      (source) => source.source == widget.currentSource && source.id == widget.currentId
    );
    
    if (currentIndex == -1) return;
    
    // 计算每个项目的高度（包括间距）
    const itemHeight = 100.0; // 每个卡片的高度
    const itemSpacing = 12.0; // 卡片间距
    const totalItemHeight = itemHeight + itemSpacing;
    
    // 计算目标位置
    final targetOffset = currentIndex * totalItemHeight;
    
    // 滚动到目标位置
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });
    _startRefreshAnimation();

    try {
      // 等待测速真正完成
      await widget.onRefresh();
    } finally {
      setState(() {
        _isRefreshing = false;
      });
      _stopRefreshAnimation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = widget.theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1c1c1e) : Colors.white,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '换源 (${widget.sources.length})',
                  style: widget.theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: RotationTransition(
                        turns: _rotationController,
                        child: Icon(
                          Icons.refresh,
                          color: _isRefreshing ? Colors.green : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                      onPressed: _isRefreshing ? null : _handleRefresh,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: widget.sources.length,
              itemBuilder: (context, index) {
                final source = widget.sources[index];
                final isCurrent = source.source == widget.currentSource && source.id == widget.currentId;
                final speedInfo = widget.sourcesSpeed['${source.source}_${source.id}'];

                return GestureDetector(
                  onTap: () => widget.onSourceTap(source),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[850] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: isCurrent
                          ? Border.all(color: Colors.green, width: 2)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        height: 100,
                        child: Stack(
                          children: [
                            Row(
                              children: [
                                // Left side: Cover
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: CachedNetworkImage(
                                      imageUrl: source.poster,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        decoration: BoxDecoration(
                                          color: isDarkMode 
                                              ? const Color(0xFF333333)
                                              : Colors.grey[300],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        decoration: BoxDecoration(
                                          color: isDarkMode 
                                              ? const Color(0xFF333333)
                                              : Colors.grey[300],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.movie,
                                          color: isDarkMode 
                                              ? const Color(0xFF666666)
                                              : Colors.grey,
                                          size: 40,
                                        ),
                                      ),
                                      fadeInDuration: const Duration(milliseconds: 200),
                                      fadeOutDuration: const Duration(milliseconds: 100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Right side: Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Title
                                      Text(
                                        source.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: widget.theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Source Name
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          source.sourceName,
                                          style: widget.theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                      const Spacer(),
                                  // Bottom row
                                  Row(
                                    children: [
                                      if (speedInfo != null) ...[
                                        if (speedInfo.loadSpeed.isNotEmpty && !speedInfo.loadSpeed.toLowerCase().contains('超时'))
                                              Text(
                                                speedInfo.loadSpeed,
                                                style: widget.theme.textTheme.bodyMedium?.copyWith(color: Colors.green),
                                              ),
                                        if (speedInfo.loadSpeed.isNotEmpty && !speedInfo.loadSpeed.toLowerCase().contains('超时') && 
                                            speedInfo.pingTime.isNotEmpty && !speedInfo.pingTime.toLowerCase().contains('超时'))
                                          const SizedBox(width: 8),
                                        if (speedInfo.pingTime.isNotEmpty && !speedInfo.pingTime.toLowerCase().contains('超时'))
                                          Text(
                                            speedInfo.pingTime,
                                            style: widget.theme.textTheme.bodyMedium?.copyWith(color: Colors.orange),
                                          ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        '${source.episodes.length} 集',
                                        style: widget.theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            // Resolution tag in top right
                            if (speedInfo != null && speedInfo.quality.isNotEmpty && speedInfo.quality.toLowerCase() != '未知')
                              Positioned(
                                top: 0,
                                right: 0,
                                  child: Text(
                                    speedInfo.quality,
                                    style: widget.theme.textTheme.bodyMedium?.copyWith(
                                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}