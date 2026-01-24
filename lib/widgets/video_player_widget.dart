import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'package:selene/widgets/mobile_player_controls.dart';
import 'package:selene/widgets/pc_player_controls.dart';
import 'package:selene/widgets/video_player_surface.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerSurface surface;
  final String? url;
  final Map<String, String>? headers;
  final VoidCallback? onBackPressed;
  final void Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final void Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final void Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final void Function(bool isPipMode)? onPipModeChanged;

  const VideoPlayerWidget({
    super.key,
    this.surface = VideoPlayerSurface.mobile,
    this.url,
    this.headers,
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
    this.onWebFullscreenChanged,
    this.onExitFullScreen,
    this.live = false,
    this.onPipModeChanged,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class VideoPlayerWidgetController {
  VideoPlayerWidgetController._(this._state);

  final _VideoPlayerWidgetState _state;

  Future<void> updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    await _state._updateDataSource(
      url,
      startAt: startAt,
      headers: headers,
    );
  }

  Future<void> seekTo(Duration position) async {
    await _state._player?.seek(position);
  }

  Duration? get currentPosition => _state._player?.state.position;

  Duration? get duration => _state._player?.state.duration;

  bool get isPlaying => _state._player?.state.playing ?? false;

  Future<void> pause() async {
    await _state._player?.pause();
  }

  Future<void> play() async {
    await _state._player?.play();
  }

  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  Future<void> setSpeed(double speed) async {
    await _state._setPlaybackSpeed(speed);
  }

  double get playbackSpeed => _state._playbackSpeed.value;

  Future<void> setVolume(double volume) async {
    await _state._player?.setVolume(volume);
  }

  double? get volume => _state._player?.state.volume;

  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }

  Future<void> dispose() async {
    await _state._externalDispose();
  }

  bool get isPipMode => _state._isPipMode;
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _hasCompleted = false;
  bool _isLoadingVideo = false;
  String? _currentUrl;
  Map<String, String>? _currentHeaders;
  final List<VoidCallback> _progressListeners = [];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  final ValueNotifier<double> _playbackSpeed = ValueNotifier<double>(1.0);
  bool _playerDisposed = false;
  VoidCallback? _exitWebFullscreenCallback;
  final Pip _pip = Pip();
  bool _isPipMode = false;

  // Store the observer instance so it can be unregistered later.
  PipStateChangedObserver? _pipObserver;

  // 视频宽高和全屏状态监听
  final ValueNotifier<BoxFit> _videoFit = ValueNotifier<BoxFit>(BoxFit.contain);
  double _videoWidth = 0;
  double _videoHeight = 0;
  Timer? _sizeCheckTimer;
  bool _isCurrentlyFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    _setupPip();
    _registerPipObserver();
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headers != oldWidget.headers && widget.headers != null) {
      _currentHeaders = widget.headers;
    }
    if (widget.url != oldWidget.url && widget.url != null) {
      unawaited(_updateDataSource(widget.url!));
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _player = Player();
    _videoController = VideoController(_player!);
    _setupPlayerListeners();
    if (_currentUrl != null) {
      await _openCurrentMedia();
    }
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }
    setState(() {
      _isLoadingVideo = true;
    });
    try {
      await _player!.open(
        Media(
          _currentUrl!,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      await _player!.setRate(_playbackSpeed.value);
      setState(() {
        _hasCompleted = false;
        // _isLoadingVideo = false;
      });
      // widget.onReady?.call();
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open media $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _setupPlayerListeners() {
    if (_player == null) {
      return;
    }
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();

    _positionSubscription = _player!.stream.position.listen((_) {
      for (final listener in List<VoidCallback>.from(_progressListeners)) {
        try {
          listener();
        } catch (error) {
          debugPrint('VideoPlayerWidget: progress listener error $error');
        }
      }
    });

    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (!mounted) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        return;
      }
      if (!playing) {
        setState(() {
          _hasCompleted = false;
        });
        _pip.setup(const PipOptions(
          autoEnterEnabled: false,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      } else {
        _pip.setup(const PipOptions(
          autoEnterEnabled: true,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      }
    });

    if (!widget.live) {
      _completedSubscription = _player!.stream.completed.listen((completed) {
        if (!mounted) return;
        if (completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onVideoCompleted?.call();
        }
      });
    }

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (!mounted) return;
      if (duration != Duration.zero) {
        if (_isLoadingVideo) {
          setState(() {
            _isLoadingVideo = false;
          });
        }
        widget.onReady?.call();
      }
    });

    // 监听视频尺寸变化并更新视频填充模式
    _sizeCheckTimer?.cancel();
    _sizeCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _playerDisposed) {
        timer.cancel();
        return;
      }
      final width = _player?.state.width ?? 0;
      final height = _player?.state.height ?? 0;
      if (width > 0 && height > 0) {
        if (_videoWidth != width || _videoHeight != height) {
          _videoWidth = width.toDouble();
          _videoHeight = height.toDouble();
          _updateVideoFitMode();
        }
      }
    });
  }

  Future<void> _updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    if (_playerDisposed) {
      return;
    }
    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    if (_player == null) {
      await _initializePlayer();
      return;
    }

    setState(() {
      _isLoadingVideo = true;
    });

    try {
      final currentSpeed = _player!.state.rate;
      await _player!.open(
        Media(
          url,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
          // _isLoadingVideo = false;
        });
      }
      // widget.onReady?.call();
    } catch (error) {
      debugPrint('VideoPlayerWidget: error while changing source $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
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

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    await _player?.setRate(speed);
  }

  /// 更新视频贴合模式
  void _updateVideoFitMode() {
    // 核心判断规则：
    // 1. 非全屏状态：始终使用 contain
    // 2. 全屏状态下：
    //    - 横屏视频（宽 > 高，如 16:9, 21:9）→ 使用 contain（等比适配，无拉伸）
    //    - 竖屏视频（高 > 宽，如 9:16, 4:5）→ 使用 scaleDown（防止超出屏幕）
    if (_videoWidth == 0 || _videoHeight == 0) return;
    final BoxFit newFit;
    if (!_isCurrentlyFullscreen) {
      // 非全屏状态，始终使用 contain
      newFit = BoxFit.contain;
    } else {
      // 全屏状态，根据视频比例决定填充模式，使用 scaleDown
      newFit = _videoWidth > _videoHeight ? BoxFit.contain : BoxFit.scaleDown;
    }
    if (_videoFit.value != newFit) {
      _videoFit.value = newFit;
    }
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  void _setupPip() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _pip.setup(const PipOptions(
      autoEnterEnabled: true,
      aspectRatioX: 16,
      aspectRatioY: 9,
      preferredContentWidth: 480,
      preferredContentHeight: 270,
      controlStyle: 2,
    ));
  }

  void _registerPipObserver() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    // Create and keep a reference to the observer so we can unregister the exact
    // same instance later. Not keeping the instance can leave native side holding
    // a callback to a Dart closure that may be collected, causing FFI crashes.
    _pipObserver = PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        if (!mounted) return;
        switch (state) {
          case PipState.pipStateStarted:
            debugPrint('PiP started successfully');
            if (mounted) {
              setState(() => _isPipMode = true);
              widget.onPipModeChanged?.call(true);
            }
            break;
          case PipState.pipStateStopped:
            debugPrint('PiP stopped');
            if (mounted) {
              setState(() {
                _isPipMode = false;
              });
              widget.onPipModeChanged?.call(false);
            }
            break;
          case PipState.pipStateFailed:
            debugPrint('PiP failed: $error');
            if (mounted) {
              setState(() => _isPipMode = false);
              widget.onPipModeChanged?.call(false);
            }
            break;
        }
      },
    );
    try {
      _pip.registerStateChangedObserver(_pipObserver!);
    } catch (e) {
      debugPrint('Failed to register PiP observer: $e');
    }
  }

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    try {
      final support = await _pip.isSupported();
      if (!support) {
        debugPrint('Device does not support PiP!');
        return;
      }
      await _player?.play();
      await _pip.start();
    } catch (e) {
      debugPrint('Failed to enter PiP mode: $e');
      _setupPip();
    }
  }

  Future<void> _externalDispose() async {
    if (!mounted || _playerDisposed) {
      return;
    }
    // Ensure PiP observer is unregistered before disposing the pip instance.
    if ((Platform.isAndroid || Platform.isIOS) && _pipObserver != null) {
      try {
        // The pip API unregisters the previously registered observer without
        // requiring the instance as an argument. Call the no-arg method to
        // ensure native callbacks are cancelled before disposing the pip
        // instance.
        await _pip.unregisterStateChangedObserver();
      } catch (e) {
        debugPrint('Failed to unregister PiP observer: $e');
      }
      _pipObserver = null;
    }
    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _playerDisposed = true;
    _sizeCheckTimer?.cancel();
    await _positionSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _completedSubscription?.cancel();
    await _durationSubscription?.cancel();
    _progressListeners.clear();
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      if (_pipObserver != null) {
        try {
          _pip.unregisterStateChangedObserver();
        } catch (e) {
          debugPrint('Failed to unregister PiP observer during dispose: $e');
        }
        _pipObserver = null;
      }
      _pip.dispose();
    }
    _disposePlayer();
    _playbackSpeed.dispose();
    _videoFit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? ValueListenableBuilder<BoxFit>(
              valueListenable: _videoFit,
              builder: (context, videoFit, _) {
                // 根据是否全屏和填充模式决定是否添加外边距
                // 全屏时无需外边距，非全屏时添加外边距防止视频超出屏幕
                final needsPadding = !_isCurrentlyFullscreen &&
                    (videoFit == BoxFit.cover || videoFit == BoxFit.scaleDown);
                final videoWidget = Video(
                  controller: _videoController!,
                  fit: videoFit,
                  controls: (state) {
                    return widget.surface == VideoPlayerSurface.desktop
                        ? PCPlayerControls(
                            state: state,
                            player: _player!,
                            onBackPressed: widget.onBackPressed,
                            onNextEpisode: widget.onNextEpisode,
                            onPause: widget.onPause,
                            videoUrl: _currentUrl ?? '',
                            isLastEpisode: widget.isLastEpisode,
                            isLoadingVideo: _isLoadingVideo,
                            onCastStarted: widget.onCastStarted,
                            videoTitle: widget.videoTitle,
                            currentEpisodeIndex: widget.currentEpisodeIndex,
                            totalEpisodes: widget.totalEpisodes,
                            sourceName: widget.sourceName,
                            onWebFullscreenChanged:
                                widget.onWebFullscreenChanged,
                            onExitWebFullscreenCallbackReady: (callback) {
                              _exitWebFullscreenCallback = callback;
                            },
                            onExitFullScreen: widget.onExitFullScreen,
                            live: widget.live,
                            playbackSpeedListenable: _playbackSpeed,
                            onSetSpeed: _setPlaybackSpeed,
                          )
                        : MobilePlayerControls(
                            player: _player!,
                            state: state,
                            onControlsVisibilityChanged: (_) {},
                            onBackPressed: widget.onBackPressed,
                            onFullscreenChange: (isFullscreen) {
                              _isCurrentlyFullscreen = isFullscreen;
                              _updateVideoFitMode();
                            },
                            onNextEpisode: widget.onNextEpisode,
                            onPause: widget.onPause,
                            videoUrl: _currentUrl ?? '',
                            isLastEpisode: widget.isLastEpisode,
                            isLoadingVideo: _isLoadingVideo,
                            onCastStarted: widget.onCastStarted,
                            videoTitle: widget.videoTitle,
                            currentEpisodeIndex: widget.currentEpisodeIndex,
                            totalEpisodes: widget.totalEpisodes,
                            sourceName: widget.sourceName,
                            onExitFullScreen: widget.onExitFullScreen,
                            live: widget.live,
                            playbackSpeedListenable: _playbackSpeed,
                            onSetSpeed: _setPlaybackSpeed,
                            onEnterPipMode: _enterPipMode,
                            isPipMode: _isPipMode,
                          );
                  },
                );
                // 条件性添加外边距
                return needsPadding
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: videoWidget,
                      )
                    : videoWidget;
              },
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }
}
