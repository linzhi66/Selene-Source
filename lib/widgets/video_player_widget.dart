import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:awesome_video_player/awesome_video_player.dart';
import 'dlna_device_dialog.dart';
import 'custom_better_player_controls.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final double aspectRatio;
  final VoidCallback? onBackPressed;
  final Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.aspectRatio = 16 / 9,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onNextEpisode,
    this.onVideoCompleted,
    this.onPause,
    this.isLastEpisode = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

/// VideoPlayerWidget 的控制器，用于外部控制播放器
class VideoPlayerWidgetController {
  final _VideoPlayerWidgetState _state;

  VideoPlayerWidgetController._(this._state);

  /// 动态更新视频播放 URL
  Future<void> updateVideoUrl(String newVideoUrl, {Duration? startAt}) async {
    await _state.updateVideoUrl(newVideoUrl, startAt: startAt);
  }

  /// 跳转到指定进度
  /// [position] 目标位置（秒）
  Future<void> seekTo(Duration position) async {
    await _state.seekTo(position);
  }

  /// 获取当前播放位置
  Duration? get currentPosition {
    return _state._betterPlayerController?.videoPlayerController?.value.position;
  }

  /// 获取视频总时长
  Duration? get duration {
    return _state._betterPlayerController?.videoPlayerController?.value.duration;
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

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  BetterPlayerController? _betterPlayerController;
  bool _isFullscreen = false;
  bool _hasCompleted = false;
  final List<VoidCallback> _progressListeners = [];
  double _cachedPlaybackSpeed = 1.0;
  String _currentVideoUrl = '';
  OverlayEntry? _fullscreenOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentVideoUrl = widget.videoUrl;
    _setPortraitOrientation();
    _initializePlayer();
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
  }

  void _setPortraitOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _setLandscapeOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _initializePlayer() async {
    if (!mounted) return;
    
    // 如果 _currentVideoUrl 为空则停止初始化直接返回
    if (_currentVideoUrl.isEmpty) return;

    final betterPlayerDataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      _currentVideoUrl,
      videoFormat: BetterPlayerVideoFormat.hls
    );

    final betterPlayerConfiguration = BetterPlayerConfiguration(
      autoPlay: true,
      looping: false,
      fullScreenByDefault: false,
      fit: BoxFit.contain,
      autoDetectFullscreenDeviceOrientation: true,
      allowedScreenSleep: false,
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
            playerController: VideoPlayerWidgetController._(this),
            videoUrl: _currentVideoUrl,
            isLastEpisode: widget.isLastEpisode,
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
      } else if (event.betterPlayerEventType == BetterPlayerEventType.hideFullscreen) {
        if (mounted && _isFullscreen) {
          setState(() {
            _isFullscreen = false;
          });
          _setPortraitOrientation();
        }
      }
    });

    setState(() {
      _isInitialized = true;
    });

    widget.onReady?.call();
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

    // 检查视频是否播放完成
    if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
      if (!_hasCompleted) {
        _hasCompleted = true;
        widget.onVideoCompleted?.call();
      }
    }
  }

  Future<void> updateVideoUrl(String newVideoUrl, {Duration? startAt}) async {
    if (!mounted) return;
    if (newVideoUrl.isEmpty) return;

    setState(() {
      _currentVideoUrl = newVideoUrl;
    });

    // 如果播放器已经初始化完成则直接 change Data Source 即可，无需重复初始化
    if (_isInitialized && _betterPlayerController != null) {
      try {
        if (_betterPlayerController!.videoPlayerController != null) {
          _cachedPlaybackSpeed = _betterPlayerController!.videoPlayerController!.value.speed;
        }

        final betterPlayerDataSource = BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          newVideoUrl,
          videoFormat: BetterPlayerVideoFormat.hls
        );

        await _betterPlayerController!.setupDataSource(betterPlayerDataSource);
        
        if (startAt != null) {
          await _betterPlayerController!.seekTo(startAt);
        }
        
        _betterPlayerController!.setSpeed(_cachedPlaybackSpeed);
        
        setState(() {
          _hasCompleted = false;
        });

        widget.onReady?.call();
      } catch (e) {
        debugPrint('Error changing data source: $e');
      }
      return;
    }

    // 如果没有初始化则直接调用 _initializePlayer 执行初始化
    await _initializePlayer();
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
    if (_isFullscreen != isFullscreen) {
      setState(() {
        _isFullscreen = isFullscreen;
      });

      if (isFullscreen) {
        _enterFullscreen();
      } else {
        _exitFullscreen();
      }
    }
  }

  void _enterFullscreen() {
    _betterPlayerController?.enterFullScreen();
  }

  void _exitFullscreen() {
    _setPortraitOrientation();
    _betterPlayerController?.exitFullScreen();
  }

  @override
  void dispose() {
    if (_isFullscreen) {
      Navigator.of(context).pop();
    }
    WidgetsBinding.instance.removeObserver(this);
    _restoreOrientation();
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
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: _buildPlayerContent(isFullscreen: _isFullscreen),
    );
  }
}