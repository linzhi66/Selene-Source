import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:awesome_video_player/awesome_video_player.dart';
import 'video_player_widget.dart';
import 'dlna_device_dialog.dart';

// LoadingVideoNotifier 已在 video_player_widget.dart 中定义，通过 import 引入

class CustomBetterPlayerControls extends StatefulWidget {
  final BetterPlayerController controller;
  final Function(bool) onControlsVisibilityChanged;
  final VoidCallback? onBackPressed;
  final Function(bool) onFullscreenChange;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPause;
  final VideoPlayerWidgetController? playerController;
  final String videoUrl;
  final bool isLastEpisode;
  final GlobalKey? betterPlayerKey;
  final bool isLoadingVideo;
  final Function(dynamic)? onCastStarted;

  const CustomBetterPlayerControls({
    super.key,
    required this.controller,
    required this.onControlsVisibilityChanged,
    this.onBackPressed,
    required this.onFullscreenChange,
    this.onNextEpisode,
    this.onPause,
    this.playerController,
    required this.videoUrl,
    this.isLastEpisode = false,
    this.betterPlayerKey,
    this.isLoadingVideo = false,
    this.onCastStarted,
  });

  @override
  State<CustomBetterPlayerControls> createState() =>
      _CustomBetterPlayerControlsState();
}

class _CustomBetterPlayerControlsState
    extends State<CustomBetterPlayerControls> {
  Timer? _hideTimer;
  bool _controlsVisible = true;
  Size? _screenSize;
  bool _lastPlayingState = false;
  bool _isLongPressing = false;
  double _originalPlaybackSpeed = 1.0;
  Duration? _dragPosition;
  bool _isSeekingViaSwipe = false;
  double _swipeStartX = 0;
  Duration _swipeStartPosition = Duration.zero;
  bool _isInPipMode = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addEventsListener(_onVideoStateChanged);
    widget.controller.videoPlayerController?.addListener(_onVideoPlayerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _forceStartHideTimer();
      }
    });
  }

  void _onVideoPlayerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  void _onVideoStateChanged(BetterPlayerEvent event) {
    if (!mounted) return;

    // 监听全屏状态变化
    if (event.betterPlayerEventType == BetterPlayerEventType.openFullscreen) {
      widget.onFullscreenChange(true);
      // 触发重建以更新UI
      if (mounted) {
        setState(() {});
      }
    } else if (event.betterPlayerEventType ==
        BetterPlayerEventType.hideFullscreen) {
      widget.onFullscreenChange(false);
      // 触发重建以更新UI
      if (mounted) {
        setState(() {});
      }
    }
    // 监听 PiP 状态变化
    else if (event.betterPlayerEventType == BetterPlayerEventType.pipStart) {
      setState(() {
        _isInPipMode = true;
        _controlsVisible = false;
      });
      _hideTimer?.cancel();
      widget.onControlsVisibilityChanged(false);
      // PiP 开始时立刻播放视频
      widget.controller.play();
    } else if (event.betterPlayerEventType == BetterPlayerEventType.pipStop) {
      // 退出 PiP 模式时立即设置为竖屏
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      setState(() {
        _isInPipMode = false;
        _controlsVisible = true;
      });
      _startHideTimer();
      widget.onControlsVisibilityChanged(true);
    }

    final isPlaying = widget.controller.isPlaying() ?? false;

    if (isPlaying != _lastPlayingState) {
      _lastPlayingState = isPlaying;

      if (_isLongPressing) return;

      if (isPlaying) {
        if (_controlsVisible) {
          _startHideTimer();
        }
      } else {
        _hideTimer?.cancel();
        if (!_controlsVisible) {
          setState(() {
            _controlsVisible = true;
          });
        }
      }
    }

    if (isPlaying && _controlsVisible && _hideTimer == null) {
      _startHideTimer();
    }

    // 确保视频播放器监听器已添加
    if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
      widget.controller.videoPlayerController
          ?.removeListener(_onVideoPlayerUpdate);
      widget.controller.videoPlayerController
          ?.addListener(_onVideoPlayerUpdate);
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (!(widget.controller.isPlaying() ?? false)) {
      return;
    }

    setState(() {
      _isLongPressing = true;
      _originalPlaybackSpeed =
          widget.controller.videoPlayerController?.value.speed ?? 1.0;
      widget.controller.setSpeed(2.0);
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isLongPressing) {
      return;
    }

    setState(() {
      _isLongPressing = false;
      widget.controller.setSpeed(_originalPlaybackSpeed);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.videoPlayerController
        ?.removeListener(_onVideoPlayerUpdate);
    widget.controller.removeEventsListener(_onVideoStateChanged);
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (widget.controller.isPlaying() ?? false) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _controlsVisible = false;
          });
          widget.onControlsVisibilityChanged(false);
        }
      });
    }
  }

  void _forceStartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _controlsVisible = false;
        });
        widget.onControlsVisibilityChanged(false);
      }
    });
  }

  void _onUserInteraction() {
    setState(() {
      _controlsVisible = true;
    });
    widget.onControlsVisibilityChanged(true);
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onBlankAreaTap() {
    if (!mounted) return;

    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    widget.onControlsVisibilityChanged(_controlsVisible);

    if (_controlsVisible) {
      _startHideTimer();
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
      _dragPosition = null;
    });
    _hideTimer?.cancel();
    _startHideTimer();
  }

  void _onSeekEnd() {
    setState(() {
      _dragPosition = null;
    });
    _startHideTimer();
  }

  void _onSwipeStart(DragStartDetails details) {
    if (!mounted) return;

    if (widget.controller.videoPlayerController?.value.hasError == true) {
      return;
    }

    setState(() {
      _isSeekingViaSwipe = true;
      _swipeStartX = details.globalPosition.dx;
      _swipeStartPosition =
          widget.controller.videoPlayerController!.value.position;
      _controlsVisible = true;
    });

    _hideTimer?.cancel();
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (!mounted || !_isSeekingViaSwipe) return;

    if (widget.controller.videoPlayerController?.value.hasError == true) {
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final swipeDistance = details.globalPosition.dx - _swipeStartX;
    final swipeRatio = swipeDistance / (screenWidth * 0.5);
    final duration = widget.controller.videoPlayerController!.value.duration!;

    final targetPosition = _swipeStartPosition +
        Duration(
            milliseconds: (duration.inMilliseconds * swipeRatio * 0.1).round());
    final clampedPosition = Duration(
        milliseconds:
            targetPosition.inMilliseconds.clamp(0, duration.inMilliseconds));

    setState(() {
      _dragPosition = clampedPosition;
    });
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (!mounted || !_isSeekingViaSwipe) return;

    if (widget.controller.videoPlayerController?.value.hasError == true) {
      setState(() {
        _isSeekingViaSwipe = false;
      });
      return;
    }

    if (_dragPosition != null) {
      widget.controller.seekTo(_dragPosition!);
    }

    setState(() {
      _isSeekingViaSwipe = false;
      _dragPosition = null;
    });

    _startHideTimer();
  }

  void _exitFullscreen() {
    if (!mounted) return;
    widget.onFullscreenChange(false);
  }

  Future<void> _showDLNADialog() async {
    // 获取当前播放位置
    final resumePos = widget.controller.videoPlayerController?.value.position;
    
    if (widget.controller.isPlaying() == true) {
      widget.controller.pause();
      widget.onPause?.call();
    }

    final isCurrentlyFullscreen = widget.controller.isFullScreen ?? false;
    if (isCurrentlyFullscreen) {
      _exitFullscreen();

      int attempts = 0;
      const maxAttempts = 20;
      while (mounted &&
          (widget.controller.isFullScreen ?? false) &&
          attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }
    }

    if (mounted && !(widget.controller.isFullScreen ?? false)) {
      await showDialog(
        context: context,
        builder: (context) => DLNADeviceDialog(
          currentUrl: widget.videoUrl,
          resumePosition: resumePos,
          onCastStarted: widget.onCastStarted,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFullscreen = widget.controller.isFullScreen ?? false;

    // 在 PIP 模式下不显示任何控件 - 使用 VideoPlayerValue 的 isPip 方法
    final isPipMode =
        widget.controller.videoPlayerController?.value.isPip ?? false;
    if (isPipMode) {
      return IgnorePointer(
        child: Container(color: Colors.transparent),
      );
    }

    // 如果正在加载视频，只显示加载界面
    if (widget.isLoadingVideo) {
      return Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                '视频加载中...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // 背景层 - 处理长按和滑动手势
        Positioned.fill(
          child: GestureDetector(
            onLongPressStart: _isInPipMode ? null : _onLongPressStart,
            onLongPressEnd: _isInPipMode ? null : _onLongPressEnd,
            onLongPressCancel: _isInPipMode
                ? null
                : () {
                    if (_isLongPressing) {
                      _onLongPressEnd(const LongPressEndDetails());
                    }
                  },
            onHorizontalDragStart: _isInPipMode ? null : _onSwipeStart,
            onHorizontalDragUpdate: _isInPipMode ? null : _onSwipeUpdate,
            onHorizontalDragEnd: _isInPipMode ? null : _onSwipeEnd,
            onTap: _isInPipMode ? null : _onBlankAreaTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
        // 长按倍速提示
        if (_isLongPressing)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '2x',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.fast_forward,
                  color: Colors.white,
                  size: isFullscreen ? 32 : 28,
                ),
              ],
            ),
          ),
        if (_controlsVisible)
          Positioned(
            top: isFullscreen ? 8 : 4,
            left: isFullscreen ? 16.0 : 8.0,
            child: GestureDetector(
              onTap: () async {
                _onUserInteraction();
                if (isFullscreen) {
                  _exitFullscreen();
                } else {
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
        if (_controlsVisible)
          Positioned(
            top: isFullscreen ? 8 : 4,
            right: isFullscreen ? 16.0 : 8.0,
            child: GestureDetector(
              onTap: () async {
                _onUserInteraction();
                await _showDLNADialog();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.cast,
                  color: Colors.white,
                  size: isFullscreen ? 24 : 20,
                ),
              ),
            ),
          ),
        if (_controlsVisible)
          Positioned(
            top: isFullscreen && _screenSize != null
                ? _screenSize!.height / 2 - 32
                : 0,
            bottom: isFullscreen ? null : 0,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  _onUserInteraction();
                  if (widget.controller.isPlaying() ?? false) {
                    widget.controller.pause();
                    widget.onPause?.call();
                  } else {
                    widget.controller.play();
                  }
                },
                child: Icon(
                  (widget.controller.isPlaying() ?? false)
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: isFullscreen ? 64 : 48,
                ),
              ),
            ),
          ),
        if (_controlsVisible)
          Positioned(
            bottom: isFullscreen ? 58.0 : 42.0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: false,
              child: Container(
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: CustomVideoProgressBar(
                  controller: widget.controller,
                  onDragStart: _onSeekStart,
                  onDragEnd: _onSeekEnd,
                  onDragUpdate: () {
                    if (!_controlsVisible) {
                      setState(() {
                        _controlsVisible = true;
                      });
                    }
                    _hideTimer?.cancel();
                  },
                  onPositionUpdate: (duration) {
                    setState(() {
                      _dragPosition = duration;
                    });
                  },
                  dragPosition: _dragPosition,
                ),
              ),
            ),
          ),
        if (_controlsVisible)
          Positioned(
            bottom: isFullscreen ? 4.0 : -6.0,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.only(
                  left: isFullscreen ? 16.0 : 8.0,
                  right: isFullscreen ? 16.0 : 8.0,
                  top: isFullscreen ? 0.0 : 0.0,
                  bottom: isFullscreen ? 8.0 : 8.0,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _onUserInteraction();
                        if (widget.controller.isPlaying() ?? false) {
                          widget.controller.pause();
                          widget.onPause?.call();
                        } else {
                          widget.controller.play();
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          (widget.controller.isPlaying() ?? false)
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: isFullscreen ? 28 : 24,
                        ),
                      ),
                    ),
                    if (!widget.isLastEpisode)
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
                    Expanded(
                      child: _buildPositionIndicator(),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.speed,
                        color: Colors.white,
                        size: isFullscreen ? 22 : 20,
                      ),
                      onPressed: () async {
                        _onUserInteraction();
                        await _showSpeedDialog();
                      },
                    ),
                    if (!isFullscreen)
                      GestureDetector(
                        onTap: () {
                          _onUserInteraction();
                          if (widget.betterPlayerKey != null) {
                            widget.controller.enablePictureInPicture(
                                widget.betterPlayerKey!);
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.picture_in_picture_alt,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () {
                        _onUserInteraction();
                        if (isFullscreen) {
                          _exitFullscreen();
                        } else {
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
      ],
    );
  }

  Widget _buildPositionIndicator() {
    final position = _dragPosition ??
        widget.controller.videoPlayerController?.value.position ??
        Duration.zero;
    final duration = widget.controller.videoPlayerController?.value.duration ??
        Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        '${_formatDuration(position)} / ${_formatDuration(duration)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Future<void> _showSpeedDialog() async {
    final speeds = [0.5, 0.75, 1.0, 1.5, 2.0];
    final currentSpeed =
        widget.controller.videoPlayerController?.value.speed ?? 1.0;

    final chosenSpeed = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: speeds.map((speed) {
                    return ListTile(
                      title: Text(
                        '${speed}x',
                        style: TextStyle(
                          color: speed == currentSpeed
                              ? Theme.of(context).primaryColor
                              : null,
                          fontWeight: speed == currentSpeed
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop(speed);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosenSpeed != null) {
      widget.controller.setSpeed(chosenSpeed);
    }
  }
}

class CustomVideoProgressBar extends StatefulWidget {
  final BetterPlayerController controller;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragUpdate;
  final Function(Duration)? onPositionUpdate;
  final Duration? dragPosition;

  const CustomVideoProgressBar({
    super.key,
    required this.controller,
    this.onDragStart,
    this.onDragEnd,
    this.onDragUpdate,
    this.onPositionUpdate,
    this.dragPosition,
  });

  @override
  State<CustomVideoProgressBar> createState() => _CustomVideoProgressBarState();
}

class _CustomVideoProgressBarState extends State<CustomVideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.videoPlayerController?.addListener(_onVideoPlayerUpdate);
    widget.controller.addEventsListener(_onBetterPlayerEvent);
  }

  void _onVideoPlayerUpdate() {
    if (mounted && !_isDragging) {
      setState(() {});
    }
  }

  void _onBetterPlayerEvent(BetterPlayerEvent event) {
    // 当视频初始化时，确保添加监听器
    if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
      widget.controller.videoPlayerController
          ?.removeListener(_onVideoPlayerUpdate);
      widget.controller.videoPlayerController
          ?.addListener(_onVideoPlayerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.videoPlayerController
        ?.removeListener(_onVideoPlayerUpdate);
    widget.controller.removeEventsListener(_onBetterPlayerEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoController = widget.controller.videoPlayerController;
    if (videoController == null || videoController.value.hasError) {
      return Container();
    }

    final duration = videoController.value.duration ?? Duration.zero;
    final position = widget.dragPosition ?? videoController.value.position;

    double value = 0.0;
    if (duration.inMilliseconds > 0) {
      value = position.inMilliseconds / duration.inMilliseconds;
    }

    if (_isDragging) {
      value = _dragValue;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (details) {
        _isDragging = true;
        widget.onDragStart?.call();
        _updateDragPosition(details.localPosition.dx, context);
      },
      onHorizontalDragUpdate: (details) {
        if (_isDragging) {
          widget.onDragUpdate?.call();
          _updateDragPosition(details.localPosition.dx, context);
        }
      },
      onHorizontalDragEnd: (details) {
        if (_isDragging) {
          _isDragging = false;
          widget.onDragEnd?.call();
          final seekPosition = Duration(
              milliseconds: (_dragValue * duration.inMilliseconds).round());
          widget.controller.seekTo(seekPosition);
        }
      },
      onTapDown: (details) {
        widget.onDragStart?.call();
        _updateDragPosition(details.localPosition.dx, context);
        final seekPosition = Duration(
            milliseconds: (_dragValue * duration.inMilliseconds).round());
        widget.controller.seekTo(seekPosition);
      },
      child: Container(
        height: 24,
        color: Colors.transparent,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = constraints.maxWidth;
              final progressValue = value.clamp(0.0, 1.0);
              final thumbPosition = (progressValue * progressWidth)
                  .clamp(8.0, progressWidth - 8.0);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 进度条背景
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ),
                  // 已播放进度
                  Positioned(
                    left: 0,
                    top: 9,
                    child: Container(
                      width: progressValue * progressWidth,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.red,
                      ),
                    ),
                  ),
                  // 可拖拽的圆形把手
                  Positioned(
                    left: thumbPosition - 8,
                    top: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _updateDragPosition(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final width = box.size.width;
    final value = (dx / width).clamp(0.0, 1.0);

    setState(() {
      _dragValue = value;
    });

    final videoController = widget.controller.videoPlayerController;
    if (videoController != null && !videoController.value.hasError) {
      final duration = videoController.value.duration ?? Duration.zero;
      final position =
          Duration(milliseconds: (value * duration.inMilliseconds).round());
      widget.onPositionUpdate?.call(position);
    }
  }
}
