import 'dart:async';
import 'package:flutter/material.dart';
import 'package:awesome_video_player/awesome_video_player.dart';
import 'custom_better_player_controls.dart';

class MobileVideoPlayerWidget extends StatefulWidget {
  final String? url;
  final VoidCallback? onBackPressed;
  final Function(MobileVideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;

  const MobileVideoPlayerWidget({
    super.key,
    this.url,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onNextEpisode,
    this.onVideoCompleted,
    this.onPause,
    this.isLastEpisode = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
  });

  @override
  State<MobileVideoPlayerWidget> createState() => _MobileVideoPlayerWidgetState();
}

/// MobileVideoPlayerWidget 的控制器，用于外部控制播放器
class MobileVideoPlayerWidgetController {
  final _MobileVideoPlayerWidgetState _state;

  MobileVideoPlayerWidgetController._(this._state);

  /// 动态更新视频数据源
  Future<void> updateDataSource(String url, {Duration? startAt}) async {
    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      videoFormat: BetterPlayerVideoFormat.hls,
    );
    startAt ??= const Duration();
    await _state.updateDataSource(dataSource, startAt: startAt);
  }

  /// 跳转到指定进度
  /// [position] 目标位置（秒）
  Future<void> seekTo(Duration position) async {
    await _state.seekTo(position);
  }

  /// 获取当前播放位置
  Duration? get currentPosition {
    return _state
        ._betterPlayerController?.videoPlayerController?.value.position;
  }

  /// 获取视频总时长
  Duration? get duration {
    return _state
        ._betterPlayerController?.videoPlayerController?.value.duration;
  }

  /// 获取播放状态
  bool get isPlaying {
    return _state._betterPlayerController?.isPlaying() ?? false;
  }

  /// 暂停播放
  void pause() {
    _state._betterPlayerController?.pause();
  }

  /// 添加视频播放进度监听器
  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  /// 移除视频播放进度监听器
  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  /// 销毁播放器资源
  void dispose() {
    _state._betterPlayerController?.dispose();
  }
}

class _MobileVideoPlayerWidgetState extends State<MobileVideoPlayerWidget>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  BetterPlayerController? _betterPlayerController;
  bool _isFullscreen = false;
  bool _hasCompleted = false;
  final List<VoidCallback> _progressListeners = [];
  double _cachedPlaybackSpeed = 1.0;
  BetterPlayerDataSource? _currentDataSource;
  final GlobalKey _betterPlayerKey = GlobalKey();
  bool _isLoadingVideo = false; // 视频加载状态

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.url != null) {
      _currentDataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url!,
        videoFormat: BetterPlayerVideoFormat.hls,
      );
    }
    _initializePlayer();
    widget.onControllerCreated?.call(MobileVideoPlayerWidgetController._(this));
  }

  Future<void> _initializePlayer({Duration? startAt}) async {
    if (!mounted) return;

    // 如果 _currentDataSource 为 null 则停止初始化直接返回
    if (_currentDataSource == null) return;

    final betterPlayerDataSource = _currentDataSource!;

    final betterPlayerConfiguration = BetterPlayerConfiguration(
      autoPlay: true,
      looping: false,
      fullScreenByDefault: false,
      fit: BoxFit.contain,
      autoDetectFullscreenDeviceOrientation: true,
      allowedScreenSleep: false,
      startAt: startAt,
      // 启用画中画模式
      handleLifecycle: false, // 禁用自动生命周期管理，让 PiP 在后台继续播放
      controlsConfiguration: BetterPlayerControlsConfiguration(
        playerTheme: BetterPlayerTheme.custom,
        customControlsBuilder: (controller, onControlsVisibilityChanged) {
          return CustomBetterPlayerControls(
            controller: controller,
            onControlsVisibilityChanged: onControlsVisibilityChanged,
            onBackPressed: widget.onBackPressed,
            onFullscreenChange: _handleFullscreenChange,
            onNextEpisode: widget.onNextEpisode,
            onPause: widget.onPause,
            playerController: MobileVideoPlayerWidgetController._(this),
            videoUrl: _currentDataSource?.url ?? '',
            isLastEpisode: widget.isLastEpisode,
            betterPlayerKey: _betterPlayerKey,
            isLoadingVideo: _isLoadingVideo,
            onCastStarted: widget.onCastStarted,
            videoTitle: widget.videoTitle,
            currentEpisodeIndex: widget.currentEpisodeIndex,
            totalEpisodes: widget.totalEpisodes,
            sourceName: widget.sourceName,
          );
        },
      ),
      eventListener: _onPlayerEvent,
    );

    _betterPlayerController = BetterPlayerController(
      betterPlayerConfiguration,
      betterPlayerDataSource: betterPlayerDataSource,
    );

    _betterPlayerController!.addEventsListener(_onPlayerEvent);

    // 监听全屏状态变化
    _betterPlayerController!.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.openFullscreen) {
        if (mounted && !_isFullscreen) {
          setState(() {
            _isFullscreen = true;
          });
        }
      } else if (event.betterPlayerEventType ==
          BetterPlayerEventType.hideFullscreen) {
        if (mounted && _isFullscreen) {
          setState(() {
            _isFullscreen = false;
          });
        }
      }
    });

    setState(() {
      _isInitialized = true;
    });
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (!mounted) return;

    // 触发进度监听器
    for (final listener in _progressListeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('Progress listener error: $e');
      }
    }

    // 监听播放器初始化完成事件
    if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
      // 隐藏加载状态
      if (mounted && _isLoadingVideo) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
      widget.onReady?.call();
    }

    // 检查视频是否播放完成
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      if (!_hasCompleted) {
        _hasCompleted = true;
        widget.onVideoCompleted?.call();
      }
    }
  }

  Future<void> updateDataSource(BetterPlayerDataSource dataSource,
      {Duration? startAt}) async {
    if (!mounted) return;

    // 显示加载状态
    setState(() {
      _currentDataSource = dataSource;
      _isLoadingVideo = true;
    });

    // 如果播放器已经初始化完成则直接 change Data Source 即可，无需重复初始化
    if (_isInitialized && _betterPlayerController != null) {
      try {
        if (_betterPlayerController!.videoPlayerController != null) {
          _cachedPlaybackSpeed =
              _betterPlayerController!.videoPlayerController!.value.speed;
        }

        await _betterPlayerController!.setupDataSource(dataSource);

        if (startAt != null) {
          await _betterPlayerController!.seekTo(startAt);
        }

        _betterPlayerController!.setSpeed(_cachedPlaybackSpeed);

        setState(() {
          _hasCompleted = false;
        });
      } catch (e) {
        debugPrint('Error changing data source: $e');
        // 出错时也隐藏加载状态
        if (mounted) {
          setState(() {
            _isLoadingVideo = false;
          });
        }
      }
      return;
    }

    // 如果没有初始化则直接调用 _initializePlayer 执行初始化
    await _initializePlayer(startAt: startAt);
  }

  Future<void> seekTo(Duration position) async {
    if (!mounted || _betterPlayerController == null) {
      return;
    }

    try {
      await _betterPlayerController!.seekTo(position);
    } catch (e) {
      debugPrint('Error seeking to position: $e');
    }
  }

  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  void _handleFullscreenChange(bool isFullscreen) {
    // 检查当前控制器的实际全屏状态
    final controllerIsFullscreen = _betterPlayerController?.isFullScreen ?? false;
    
    if (isFullscreen && !controllerIsFullscreen) {
      // 需要进入全屏
      setState(() {
        _isFullscreen = true;
      });
      _enterFullscreen();
    } else if (!isFullscreen && controllerIsFullscreen) {
      // 需要退出全屏
      setState(() {
        _isFullscreen = false;
      });
      _exitFullscreen();
    } else if (!isFullscreen && !controllerIsFullscreen) {
      // 系统返回键已经退出全屏，只需要同步状态
      if (_isFullscreen) {
        setState(() {
          _isFullscreen = false;
        });
      }
    }
  }

  void _enterFullscreen() {
    _betterPlayerController?.enterFullScreen();
  }

  void _exitFullscreen() {
    _betterPlayerController?.exitFullScreen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 在 iOS 上，当 app 进入后台时，如果正在使用 PiP，不要暂停播放
    // BetterPlayer 会自动处理 PiP 的状态，我们只需要确保不干扰它
    if (_betterPlayerController == null) return;
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // app 进入后台或不活跃状态
        // 不做任何操作，让 PiP 继续播放
        break;
      case AppLifecycleState.resumed:
        // app 恢复到前台
        // 不做任何操作，保持当前播放状态
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      Navigator.of(context).pop();
    }
    WidgetsBinding.instance.removeObserver(this);
    _progressListeners.clear();
    _betterPlayerController?.dispose();
    super.dispose();
  }

  Widget _buildPlayerContent({required bool isFullscreen}) {
    return Container(
      color: Colors.black,
      child: _isInitialized && _betterPlayerController != null
          ? BetterPlayer(
              controller: _betterPlayerController!,
              key: _betterPlayerKey,
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildPlayerContent(isFullscreen: _isFullscreen);
  }
}
