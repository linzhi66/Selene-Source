import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chewie/chewie.dart';

// ignore: implementation_imports
import 'package:chewie/src/material/widgets/playback_speed_dialog.dart';
import 'package:chewie/src/progress_bar.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final double aspectRatio;
  final VoidCallback? onBackPressed;
  final Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;

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
    return _state._videoController?.value.position;
  }

  /// 获取视频总时长
  Duration? get duration {
    return _state._videoController?.value.duration;
  }

  /// 获取播放状态
  bool get isPlaying {
    return _state._videoController?.value.isPlaying ?? false;
  }

  /// 暂停播放
  void pause() {
    _state._chewieController?.pause();
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
    _state._videoController?.dispose();
    _state._chewieController?.dispose();
  }
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isFullscreen = false;
  bool _hasCompleted = false; // 防止重复触发完成事件
  final List<VoidCallback> _progressListeners = []; // 进度监听器列表
  double _cachedPlaybackSpeed = 1.0; // 暂存的播放速率

  @override
  void initState() {
    super.initState();
    // 添加应用生命周期观察者
    WidgetsBinding.instance.addObserver(this);

    // 设置初始屏幕方向为竖屏
    _setPortraitOrientation();

    // 创建控制器并通知父组件
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
  }

  // 设置竖屏方向
  void _setPortraitOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // 设置横屏方向
  void _setLandscapeOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // 恢复屏幕方向为自动
  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 动态更新视频播放 URL
  /// [newVideoUrl] 新的视频 URL
  /// [startAt] 开始播放时间，如果提供则从指定时间开始播放
  Future<void> updateVideoUrl(String newVideoUrl, {Duration? startAt}) async {
    if (!mounted) return;
    if (newVideoUrl.isEmpty) return;

    // 保存当前全屏状态和播放速率
    final wasFullscreen = _isFullscreen;
    if (_videoController != null && _videoController!.value.isInitialized) {
      _cachedPlaybackSpeed = _videoController!.value.playbackSpeed;
    }

    // 如果当前在全屏状态，先退出全屏
    if (wasFullscreen && _chewieController != null) {
      _chewieController!.exitFullScreen();
      // 等待退出全屏完成
      await Future.delayed(const Duration(milliseconds: 300));
    }

    try {
      // 先移除监听器，再释放控制器
      _videoController?.removeListener(_onVideoStateChanged);
      _chewieController?.dispose();
      _videoController?.dispose();

      // 重置状态
      setState(() {
        _isInitialized = false;
        _hasCompleted = false;
        _isFullscreen = false; // 确保全屏状态被重置
      });

      // 创建新的控制器
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(newVideoUrl),
      );

      await _videoController!.initialize();

      if (mounted) {
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowMuting: true,
          allowPlaybackSpeedChanging: true,
          showOptions: true,
          showControlsOnInitialize: true,
          startAt: startAt,
          allowedScreenSleep: false,
          customControls: CustomChewieControls(
            onBackPressed: widget.onBackPressed,
            onFullscreenChange: _handleFullscreenChange,
            onNextEpisode: widget.onNextEpisode,
            onPause: widget.onPause,
            playerController: VideoPlayerWidgetController._(this),
          ),
        );

        // 恢复播放速率
        _videoController!.setPlaybackSpeed(_cachedPlaybackSpeed);

        // 添加视频播放完成监听
        _videoController!.addListener(_onVideoStateChanged);

        setState(() {
          _isInitialized = true;
        });

        // 触发 ready 事件
        widget.onReady?.call();

        // 如果之前是全屏状态，等待 ready 后重新进入全屏
        if (wasFullscreen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _chewieController != null) {
              // 延迟一点时间确保播放器完全准备好
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && _chewieController != null) {
                  _chewieController!.enterFullScreen();
                }
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error updating video URL: $e');
      // 如果更新失败，保持当前状态
      setState(() {
        _isInitialized = false;
      });
    }
  }

  /// 跳转到指定进度
  /// [position] 目标位置
  Future<void> seekTo(Duration position) async {
    if (!mounted ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return;
    }

    try {
      await _videoController!.seekTo(position);
    } catch (e) {
      debugPrint('Error seeking to position: $e');
    }
  }

  // 处理视频状态变化
  void _onVideoStateChanged() {
    if (!mounted ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return;
    }

    final value = _videoController!.value;

    // 触发进度监听器
    for (final listener in _progressListeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('Progress listener error: $e');
      }
    }

    // 检查视频是否播放完成
    if (value.position >= value.duration && value.duration.inMilliseconds > 0) {
      if (!_hasCompleted) {
        _hasCompleted = true;
        widget.onVideoCompleted?.call();
      }
    }
  }

  /// 添加进度监听器
  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  /// 移除进度监听器
  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  // 处理全屏状态变化
  void _handleFullscreenChange(bool isFullscreen) {
    if (_isFullscreen != isFullscreen) {
      setState(() {
        _isFullscreen = isFullscreen;
      });

      // 根据全屏状态设置屏幕方向
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isFullscreen) {
          // 进入全屏时根据视频分辨率判断屏幕方向
          _setOrientationBasedOnVideo();
        } else {
          // 退出全屏时强制进入竖屏
          _setPortraitOrientation();
        }
      });
    }
  }

  // 根据视频分辨率设置屏幕方向
  void _setOrientationBasedOnVideo() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      // 如果视频未初始化，默认使用横屏
      _setLandscapeOrientation();
      return;
    }

    final videoSize = _videoController!.value.size;
    final aspectRatio = videoSize.width / videoSize.height;

    // 判断是否为竖屏视频（宽高比小于1）
    if (aspectRatio < 1.0) {
      // 竖屏视频，设置竖屏方向
      _setPortraitOrientation();
    } else {
      // 横屏视频，设置横屏方向
      _setLandscapeOrientation();
    }
  }

  @override
  void dispose() {
    // 移除应用生命周期观察者
    WidgetsBinding.instance.removeObserver(this);

    // 恢复屏幕方向为自动
    _restoreOrientation();
    // 清理进度监听器
    _progressListeners.clear();
    // 移除监听器
    _videoController?.removeListener(_onVideoStateChanged);
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Container(
        color: Colors.black,
        child: _isInitialized && _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

class CustomChewieControls extends StatefulWidget {
  final VoidCallback? onBackPressed;
  final Function(bool) onFullscreenChange;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPause;
  final VideoPlayerWidgetController? playerController;

  const CustomChewieControls({
    super.key,
    this.onBackPressed,
    required this.onFullscreenChange,
    this.onNextEpisode,
    this.onPause,
    this.playerController,
  });

  @override
  State<CustomChewieControls> createState() => _CustomChewieControlsState();
}

class _CustomChewieControlsState extends State<CustomChewieControls> {
  Timer? _hideTimer;
  bool _controlsVisible = true;
  Size? _screenSize; // 缓存屏幕尺寸
  ChewieController? _chewieController;
  bool _lastPlayingState = false; // 记录上次的播放状态，避免重复触发

  bool _isLongPressing = false;
  double _originalPlaybackSpeed = 1.0;
  Duration? _dragPosition; // 拖动时的位置
  bool _isSeekingViaSwipe = false; // 是否正在通过滑动进行seek
  double _swipeStartX = 0; // 滑动开始时的X坐标
  Duration _swipeStartPosition = Duration.zero; // 滑动开始时的播放位置

  @override
  void initState() {
    super.initState();
    // 延迟启动定时器，确保控制器已经初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _forceStartHideTimer();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在didChangeDependencies中安全地获取屏幕尺寸
    _screenSize = MediaQuery.of(context).size;

    // 获取 ChewieController
    final chewieController = ChewieController.of(context);

    // 如果控制器发生变化，先移除旧监听器
    if (_chewieController != null && _chewieController != chewieController) {
      _chewieController!.videoPlayerController
          .removeListener(_onVideoStateChanged);
    }

    _chewieController = chewieController;

    // 添加视频状态变化监听器
    if (_chewieController != null) {
      _chewieController!.videoPlayerController
          .addListener(_onVideoStateChanged);
    }
  }

  void _onVideoStateChanged() {
    // 检查widget是否仍然mounted
    if (!mounted) return;

    final isPlaying =
        _chewieController?.videoPlayerController.value.isPlaying ?? false;

    // 只在播放状态真正改变时才处理，避免频繁触发
    if (isPlaying != _lastPlayingState) {
      _lastPlayingState = isPlaying;

      // 长按期间不处理自动隐藏逻辑
      if (_isLongPressing) return;

      if (isPlaying) {
        // 视频开始播放时，如果控件可见则启动定时器
        if (_controlsVisible) {
          _startHideTimer();
        }
      } else {
        // 视频暂停时，停止定时器并显示控件
        _hideTimer?.cancel();
        if (!_controlsVisible) {
          setState(() {
            _controlsVisible = true;
          });
        }
      }
    }

    // 如果视频正在播放且控件可见但没有定时器在运行，启动定时器
    if (isPlaying && _controlsVisible && _hideTimer == null) {
      _startHideTimer();
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final chewieController = _chewieController;
    if (chewieController == null ||
        !chewieController.videoPlayerController.value.isPlaying) {
      return;
    }

    setState(() {
      _isLongPressing = true;
      _originalPlaybackSpeed =
          chewieController.videoPlayerController.value.playbackSpeed;
      chewieController.videoPlayerController.setPlaybackSpeed(3.0);
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    final chewieController = _chewieController;
    if (chewieController == null || !_isLongPressing) {
      return;
    }

    setState(() {
      _isLongPressing = false;
      chewieController.videoPlayerController
          .setPlaybackSpeed(_originalPlaybackSpeed);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    // 只在视频播放时启动自动隐藏定时器
    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _controlsVisible = false;
          });
        }
      });
    }
  }

  // 强制启动隐藏定时器（用于初始化时）
  void _forceStartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  void _onUserInteraction() {
    // 用户交互时始终显示控件并重置定时器
    setState(() {
      _controlsVisible = true;
    });
    _startHideTimer();
    // 强制触发一次UI更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onBlankAreaTap() {
    // 检查widget是否仍然mounted
    if (!mounted) return;

    // 点击空白区域时切换控件显示状态
    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_controlsVisible) {
      _startHideTimer();
      // 强制触发一次UI更新
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onSeekStart() {
    if (!mounted) return;
    setState(() {
      _controlsVisible = true;
      _dragPosition = null; // 清空拖动位置
    });
    _hideTimer?.cancel();
    // 拖拽开始也是用户交互，需要重置定时器
    _startHideTimer();
  }

  void _onSeekEnd() {
    setState(() {
      _dragPosition = null; // 清空拖动位置
    });
    _startHideTimer();
  }

  // 处理空白区域水平滑动开始
  void _onSwipeStart(DragStartDetails details) {
    if (!mounted) return;

    final chewieController = _chewieController;
    if (chewieController == null || !chewieController.videoPlayerController.value.isInitialized) {
      return;
    }

    setState(() {
      _isSeekingViaSwipe = true;
      _swipeStartX = details.globalPosition.dx;
      _swipeStartPosition = chewieController.videoPlayerController.value.position;
      _controlsVisible = true; // 显示控件
    });

    _hideTimer?.cancel(); // 取消自动隐藏定时器
  }

  // 处理空白区域水平滑动更新
  void _onSwipeUpdate(DragUpdateDetails details) {
    if (!mounted || !_isSeekingViaSwipe) return;

    final chewieController = _chewieController;
    if (chewieController == null || !chewieController.videoPlayerController.value.isInitialized) {
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final swipeDistance = details.globalPosition.dx - _swipeStartX;

    // 计算滑动比例：每100像素代表10%的视频时长变化
    final swipeRatio = swipeDistance / (screenWidth * 0.5); // 半屏宽度代表100%变化
    final duration = chewieController.videoPlayerController.value.duration;

    // 计算目标位置
    final targetPosition = _swipeStartPosition + Duration(milliseconds: (duration.inMilliseconds * swipeRatio * 0.1).round());
    final clampedPosition = Duration(milliseconds: targetPosition.inMilliseconds.clamp(0, duration.inMilliseconds));

    setState(() {
      _dragPosition = clampedPosition; // 更新拖动位置显示
    });
  }

  // 处理空白区域水平滑动结束
  void _onSwipeEnd(DragEndDetails details) {
    if (!mounted || !_isSeekingViaSwipe) return;

    final chewieController = _chewieController;
    if (chewieController == null || !chewieController.videoPlayerController.value.isInitialized) {
      setState(() {
        _isSeekingViaSwipe = false;
      });
      return;
    }

    // 如果有拖动位置，跳转到该位置
    if (_dragPosition != null) {
      chewieController.videoPlayerController.seekTo(_dragPosition!);
    }

    setState(() {
      _isSeekingViaSwipe = false;
      _dragPosition = null;
    });

    _startHideTimer(); // 重新开始自动隐藏定时器
  }

  // 退出全屏
  void _exitFullscreen() {
    // 检查widget是否仍然mounted
    if (!mounted) return;

    // 退出全屏，屏幕方向会在_handleFullscreenChange中处理
    _chewieController?.exitFullScreen();

    // 通知父组件全屏状态变化
    widget.onFullscreenChange(false);
  }

  @override
  Widget build(BuildContext context) {
    final chewieController = ChewieController.of(context);
    final isFullscreen = chewieController.isFullScreen;

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: () {
        if (_isLongPressing) {
          _onLongPressEnd(const LongPressEndDetails());
        }
      },
      // 添加水平滑动处理
      onHorizontalDragStart: _onSwipeStart,
      onHorizontalDragUpdate: _onSwipeUpdate,
      onHorizontalDragEnd: _onSwipeEnd,
      child: Stack(
        children: [
          // 全屏点击区域 - 始终存在，用于显示/隐藏控件
          // 排除进度条区域，避免点击冲突
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            // 非全屏时排除底部50px区域（进度条+按钮区域）
            child: GestureDetector(
              onTap: _onBlankAreaTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          // 全屏渐变效果
          if (_controlsVisible)
            Positioned.fill(
              child: GestureDetector(
                onTap: _onBlankAreaTap,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.5), // 顶部黑色
                        Colors.transparent, // 中间无色
                        Colors.black.withValues(alpha: 0.1), // 底部黑色
                      ],
                      stops: const [0.0, 0.5, 1.0], // 控制渐变位置
                    ),
                  ),
                ),
              ),
            ),
          // 返回按钮
          if (_controlsVisible)
            Positioned(
              top: isFullscreen ? 8 : 4,
              left: isFullscreen ? 16.0 : 8.0,
              child: GestureDetector(
                onTap: () async {
                  _onUserInteraction();
                  // 如果处于全屏状态，则退出全屏
                  if (isFullscreen) {
                    _exitFullscreen();
                  } else {
                    // 否则调用父组件的返回回调
                    widget.onBackPressed?.call();
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: isFullscreen ? 24 : 20,
                  ),
                ),
              ),
            ),
          // 居中播放按钮
          if (_controlsVisible)
            Positioned(
              top: isFullscreen && _screenSize != null
                  ? _screenSize!.height / 2 - 32 // 全屏时使用屏幕中心
                  : 0,
              // 非全屏时从顶部开始
              bottom: isFullscreen
                  ? null // 全屏时不设置bottom
                  : 0,
              // 非全屏时从底部开始，配合top=0实现垂直居中
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _onUserInteraction();
                    if (chewieController
                        .videoPlayerController.value.isPlaying) {
                      chewieController.pause();
                      widget.onPause?.call();
                    } else {
                      chewieController.play();
                    }
                  },
                  child: AnimatedBuilder(
                    animation: chewieController.videoPlayerController,
                    builder: (context, child) {
                      return Icon(
                        chewieController.videoPlayerController.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: isFullscreen ? 64 : 48,
                      );
                    },
                  ),
                ),
              ),
            ),
          // 进度条
          if (_controlsVisible)
            Positioned(
              bottom: isFullscreen ? 58.0 : 42.0,
              left: 0,
              right: 0,
              child: Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: CustomVideoProgressBar(
                  chewieController.videoPlayerController,
                  barHeight: 6,
                  handleHeight: 6,
                  colors: ChewieProgressColors(
                    playedColor: Colors.red,
                    handleColor: Colors.red,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    bufferedColor: Colors.transparent,
                  ),
                  onDragStart: _onSeekStart,
                  onDragEnd: _onSeekEnd,
                  onDragUpdate: () {
                    // 拖拽过程中保持控件可见并重置定时器
                    if (!_controlsVisible) {
                      setState(() {
                        _controlsVisible = true;
                      });
                    }
                    // 拖拽过程中重置定时器，避免在拖拽时自动隐藏
                    _hideTimer?.cancel();
                  },
                  onPositionUpdate: (duration) {
                    // 更新拖动位置
                    setState(() {
                      _dragPosition = duration;
                    });
                  },
                  dragPosition: _dragPosition, // 传入拖动位置
                ),
              ),
            ),
          // 底部控件
          if (_controlsVisible)
            Positioned(
              bottom: isFullscreen ? 0 : -12,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  // 阻止点击事件冒泡到空白区域
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isFullscreen ? 16.0 : 8.0,
                      right: isFullscreen ? 16.0 : 8.0,
                      top: isFullscreen ? 0.0 : 0.0,
                      bottom: isFullscreen ? 8.0 : 10.0,
                    ),
                    child: Row(
                      children: [
                        // 播放按钮
                        GestureDetector(
                          onTap: () {
                            _onUserInteraction();
                            if (chewieController
                                .videoPlayerController.value.isPlaying) {
                              chewieController.pause();
                              widget.onPause?.call();
                            } else {
                              chewieController.play();
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: AnimatedBuilder(
                              animation: chewieController.videoPlayerController,
                              builder: (context, child) {
                                return Icon(
                                  chewieController
                                          .videoPlayerController.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.white,
                                  size: isFullscreen ? 28 : 24,
                                );
                              },
                            ),
                          ),
                        ),
                        // 下一集按钮
                        Transform.translate(
                          offset: const Offset(-8, 0),
                          child: GestureDetector(
                            onTap: () {
                              _onUserInteraction();
                              widget.onNextEpisode?.call();
                            },
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.skip_next,
                                color: Colors.white,
                                size: isFullscreen ? 28 : 24,
                              ),
                            ),
                          ),
                        ),
                        // 位置指示器
                        Expanded(
                          child: _buildPositionIndicator(chewieController),
                        ),
                        // 倍速按钮
                        IconButton(
                          icon: Icon(
                            Icons.speed,
                            color: Colors.white,
                            size: isFullscreen ? 22 : 20,
                          ),
                          onPressed: () async {
                            _onUserInteraction();
                            final videoController =
                                chewieController.videoPlayerController;
                            final chosenSpeed =
                                await showModalBottomSheet<double>(
                              context: context,
                              isScrollControlled: true,
                              useRootNavigator:
                                  chewieController.useRootNavigator,
                              builder: (context) => PlaybackSpeedDialog(
                                speeds: const [0.5, 0.75, 1.0, 1.5, 2.0, 3.0],
                                selected: videoController.value.playbackSpeed,
                              ),
                            );
                            if (chosenSpeed != null) {
                              videoController.setPlaybackSpeed(chosenSpeed);
                            }
                          },
                        ),
                        // 全屏按钮
                        GestureDetector(
                          onTap: () {
                            _onUserInteraction();
                            if (isFullscreen) {
                              _exitFullscreen();
                            } else {
                              chewieController.enterFullScreen();
                              widget.onFullscreenChange(true);
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              isFullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              color: Colors.white,
                              size: isFullscreen ? 28 : 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 滑动seeking时的视觉反馈
          if (_isSeekingViaSwipe)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.fast_rewind,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '滑动调整进度',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.fast_forward,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 24,
                  ),
                ],
              ),
            ),
          if (_isLongPressing)
            Positioned(
              // child: Text("倍速播放"),
              top: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '3x',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.fast_forward,
                    color: Colors.white,
                    size: isFullscreen ? 64 : 48,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPositionIndicator(ChewieController chewieController) {
    final videoPlayerController = chewieController.videoPlayerController;

    return AnimatedBuilder(
      animation: videoPlayerController,
      builder: (context, child) {
        // 如果有拖动位置，使用拖动位置，否则使用当前播放位置
        final currentPosition = _dragPosition ?? videoPlayerController.value.position;
        final totalDuration = videoPlayerController.value.duration;

        return Text(
          '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }
}

class CustomVideoProgressBar extends StatefulWidget {
  CustomVideoProgressBar(
    this.controller, {
    super.key,
    this.barHeight = 5,
    this.handleHeight = 6,
    ChewieProgressColors? colors,
    this.onDragEnd,
    this.onDragStart,
    this.onDragUpdate,
    this.draggableProgressBar = true,
    this.onPositionUpdate,
    this.dragPosition,
  }) : colors = colors ?? ChewieProgressColors();

  final double barHeight;
  final double handleHeight;
  final VideoPlayerController controller;
  final ChewieProgressColors colors;
  final Function()? onDragStart;
  final Function()? onDragEnd;
  final Function()? onDragUpdate;
  final Function(Duration)? onPositionUpdate;
  final Duration? dragPosition;
  final bool draggableProgressBar;

  @override
  State<CustomVideoProgressBar> createState() => _CustomVideoProgressBarState();
}

class _CustomVideoProgressBarState extends State<CustomVideoProgressBar> {
  void listener() {
    if (!mounted) return;
    setState(() {});
  }

  bool _controllerWasPlaying = false;
  Offset? _latestDraggableOffset;

  VideoPlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(listener);
  }

  @override
  void deactivate() {
    controller.removeListener(listener);
    super.deactivate();
  }

  void _seekToRelativePosition(Offset globalPosition) {
    final position = context.calculateRelativePosition(controller.value.duration, globalPosition);
    controller.seekTo(position);
  }

  @override
  Widget build(BuildContext context) {
    // 如果有拖动位置，创建一个修改过的VideoPlayerValue来显示拖动位置
    final displayValue = widget.dragPosition != null
        ? controller.value.copyWith(position: widget.dragPosition!)
        : controller.value;

    final child = Center(
      child: StaticProgressBar(
        value: displayValue,
        colors: widget.colors,
        barHeight: widget.barHeight,
        handleHeight: widget.handleHeight,
        drawShadow: true,
        latestDraggableOffset: _latestDraggableOffset,
      ),
    );

    return widget.draggableProgressBar
        ? GestureDetector(
            onHorizontalDragStart: (DragStartDetails details) {
              if (!controller.value.isInitialized) {
                return;
              }
              _controllerWasPlaying = controller.value.isPlaying;
              if (_controllerWasPlaying) {
                controller.pause();
              }

              widget.onDragStart?.call();
            },
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              if (!controller.value.isInitialized) {
                return;
              }
              _latestDraggableOffset = details.globalPosition;

              // 计算当前拖动位置并通知外部
              final dragPosition = context.calculateRelativePosition(controller.value.duration, details.globalPosition);
              widget.onPositionUpdate?.call(dragPosition);

              listener();
              widget.onDragUpdate?.call();
            },
            onHorizontalDragEnd: (DragEndDetails details) {
              if (_controllerWasPlaying) {
                controller.play();
              }

              if (_latestDraggableOffset != null) {
                _seekToRelativePosition(_latestDraggableOffset!);
                _latestDraggableOffset = null;
              }

              widget.onDragEnd?.call();
            },
            onTapDown: (TapDownDetails details) {
              if (!controller.value.isInitialized) {
                return;
              }
              _seekToRelativePosition(details.globalPosition);
            },
            child: child,
          )
        : child;
  }
}

extension RelativePositionExtensions on BuildContext {
  Duration calculateRelativePosition(Duration videoDuration, Offset globalPosition) {
    final box = findRenderObject()! as RenderBox;
    final Offset tapPos = box.globalToLocal(globalPosition);
    final double relative = (tapPos.dx / box.size.width).clamp(0, 1);
    final Duration position = videoDuration * relative;
    return position;
  }
}
