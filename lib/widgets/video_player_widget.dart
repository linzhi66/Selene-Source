import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'package:selene/components/animations/video_loading_animation.dart';
import 'package:selene/services/download_service.dart';
import 'package:selene/widgets/mobile_player_controls.dart';
import 'package:selene/widgets/pc_player_controls.dart';
import 'package:selene/widgets/video_player_surface.dart';

/// 下载状态枚举
enum VideoDownloadState {
  idle,
  downloading,
  paused,
  completed,
  failed,
}

/// 下载信息类
class VideoDownloadInfo {
  final String? taskId;
  final VideoDownloadState state;
  final double progress;
  final String? filePath;
  final String? errorMessage;

  const VideoDownloadInfo({
    this.taskId,
    this.state = VideoDownloadState.idle,
    this.progress = 0.0,
    this.filePath,
    this.errorMessage,
  });

  VideoDownloadInfo copyWith({
    String? taskId,
    VideoDownloadState? state,
    double? progress,
    String? filePath,
    String? errorMessage,
  }) {
    return VideoDownloadInfo(
      taskId: taskId ?? this.taskId,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

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
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;
  // ignore: avoid_positional_boolean_parameters
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

  // ===== 下载控制接口 =====

  /// 获取当前下载信息
  VideoDownloadInfo get downloadInfo => _state._downloadInfo;

  /// 开始下载当前视频
  Future<void> startDownload({String? fileName}) async {
    await _state._startDownload(fileName: fileName);
  }

  /// 暂停下载
  Future<void> pauseDownload() async {
    await _state._pauseDownload();
  }

  /// 恢复下载
  Future<void> resumeDownload() async {
    await _state._resumeDownload();
  }

  /// 取消下载
  Future<void> cancelDownload() async {
    await _state._cancelDownload();
  }

  /// 另存为
  Future<String?> saveAs() async {
    return _state._saveAs();
  }

  /// 添加下载状态监听
  void addDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    _state._addDownloadListener(listener);
  }

  /// 移除下载状态监听
  void removeDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    _state._removeDownloadListener(listener);
  }
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
  final List<VoidCallback> _progressListeners = <VoidCallback>[];
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

  // ===== 下载相关 =====
  final DownloadService _downloadService = DownloadService();
  VideoDownloadInfo _downloadInfo = const VideoDownloadInfo();
  final List<ValueChanged<VideoDownloadInfo>> _downloadListeners =
      <ValueChanged<VideoDownloadInfo>>[];

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
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }
    if (mounted) {
      setState(() {
        _isLoadingVideo = true;
      });
    }
    try {
      await _player!.open(
        Media(
          _currentUrl!,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
      );
      await _player!.setRate(_playbackSpeed.value);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
        });
      }
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
        _pip.setup(
          const PipOptions(
            autoEnterEnabled: false,
            aspectRatioX: 16,
            aspectRatioY: 9,
            preferredContentWidth: 480,
            preferredContentHeight: 270,
            controlStyle: 2,
          ),
        );
      } else {
        _pip.setup(
          const PipOptions(
            autoEnterEnabled: true,
            aspectRatioX: 16,
            aspectRatioY: 9,
            preferredContentWidth: 480,
            preferredContentHeight: 270,
            controlStyle: 2,
          ),
        );
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
    _sizeCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
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
      },
    );
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

    // 取消之前的下载
    await _cancelDownload();

    if (_player == null) {
      await _initializePlayer();
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingVideo = true;
      });
    }

    try {
      final currentSpeed = _player!.state.rate;
      await _player!.open(
        Media(
          url,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
      );
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
        });
      }
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
    if (_videoWidth == 0 || _videoHeight == 0) return;
    final BoxFit newFit;
    if (!_isCurrentlyFullscreen) {
      newFit = BoxFit.contain;
    } else {
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
    _pip.setup(
      const PipOptions(
        autoEnterEnabled: true,
        aspectRatioX: 16,
        aspectRatioY: 9,
        preferredContentWidth: 480,
        preferredContentHeight: 270,
        controlStyle: 2,
      ),
    );
  }

  void _registerPipObserver() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
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
    // 取消下载
    await _cancelDownload();

    if ((Platform.isAndroid || Platform.isIOS) && _pipObserver != null) {
      try {
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

  // ===== 下载功能实现 =====

  void _addDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    if (!_downloadListeners.contains(listener)) {
      _downloadListeners.add(listener);
    }
  }

  void _removeDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    _downloadListeners.remove(listener);
  }

  void _notifyDownloadListeners() {
    for (final listener in List<ValueChanged<VideoDownloadInfo>>.of(
      _downloadListeners,
    )) {
      try {
        listener(_downloadInfo);
      } catch (e) {
        debugPrint('Download listener error: $e');
      }
    }
  }

  void _updateDownloadInfo(VideoDownloadInfo info) {
    if (mounted) {
      setState(() {
        _downloadInfo = info;
      });
    } else {
      _downloadInfo = info;
    }
    _notifyDownloadListeners();
  }

  Future<void> _startDownload({String? fileName}) async {
    if (_currentUrl == null) return;

    // 检查是否已有下载任务
    if (_downloadInfo.taskId != null) {
      final existingTask = _downloadService.getTask(_downloadInfo.taskId!);
      if (existingTask != null &&
          (existingTask.status == DownloadStatus.downloading ||
              existingTask.status == DownloadStatus.completed)) {
        return;
      }
    }

    // 生成文件名
    final targetFileName = fileName ??
        widget.videoTitle ??
        'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // 确保有正确的扩展名
    var finalFileName = targetFileName;
    if (!finalFileName.contains('.')) {
      final isM3u8 = _currentUrl!.toLowerCase().endsWith('.m3u8');
      finalFileName = '$finalFileName.${isM3u8 ? 'mp4' : 'mp4'}';
    }

    // 开始下载
    final task = await _downloadService.startDownload(
      url: _currentUrl!,
      fileName: finalFileName,
      headers: _currentHeaders,
      episodeInfo: widget.currentEpisodeIndex != null
          ? 'EP${widget.currentEpisodeIndex}'
          : null,
    );

    if (task != null) {
      _updateDownloadInfo(
        VideoDownloadInfo(
          taskId: task.id,
          state: VideoDownloadState.downloading,
        ),
      );

      // 添加监听器
      _downloadService.addListener(task.id, _onDownloadTaskUpdate);
    }
  }

  void _onDownloadTaskUpdate(DownloadTask task) {
    if (!mounted) return;

    VideoDownloadState state;
    switch (task.status) {
      case DownloadStatus.waiting:
        state = VideoDownloadState.idle;
      case DownloadStatus.downloading:
        state = VideoDownloadState.downloading;
      case DownloadStatus.paused:
        state = VideoDownloadState.paused;
      case DownloadStatus.completed:
        state = VideoDownloadState.completed;
      case DownloadStatus.failed:
        state = VideoDownloadState.failed;
    }

    _updateDownloadInfo(
      _downloadInfo.copyWith(
        state: state,
        progress: task.progress,
        errorMessage: task.errorMessage,
      ),
    );
  }

  Future<void> _pauseDownload() async {
    if (_downloadInfo.taskId == null) return;
    await _downloadService.pauseDownload(_downloadInfo.taskId!);
  }

  Future<void> _resumeDownload() async {
    if (_downloadInfo.taskId == null) return;
    await _downloadService.resumeDownload(_downloadInfo.taskId!);
  }

  Future<void> _cancelDownload() async {
    if (_downloadInfo.taskId == null) {
      _updateDownloadInfo(const VideoDownloadInfo());
      return;
    }

    // 移除监听器
    _downloadService.removeListener(
      _downloadInfo.taskId!,
      _onDownloadTaskUpdate,
    );

    // 取消下载（会删除临时文件）
    await _downloadService.cancelDownload(_downloadInfo.taskId!);

    _updateDownloadInfo(const VideoDownloadInfo());
  }

  /// 在 dispose 时清理下载资源（不调用 setState）
  void _disposeDownload() {
    if (_downloadInfo.taskId == null) return;

    // 移除监听器
    _downloadService.removeListener(
      _downloadInfo.taskId!,
      _onDownloadTaskUpdate,
    );

    // 取消下载（会删除临时文件）- 不等待完成，避免阻塞 dispose
    unawaited(_downloadService.cancelDownload(_downloadInfo.taskId!));
  }

  Future<String?> _saveAs() async {
    if (_downloadInfo.taskId == null) return null;

    // 先自动保存到默认位置
    final autoPath = await _downloadService.autoSave(_downloadInfo.taskId!);
    if (autoPath == null) return null;

    _updateDownloadInfo(
      _downloadInfo.copyWith(filePath: autoPath),
    );

    // 然后让用户选择另存为位置（桌面端）或保存到相册（移动端）
    final userPath = await _downloadService.saveAs(_downloadInfo.taskId!);
    if (userPath != null) {
      _updateDownloadInfo(
        _downloadInfo.copyWith(filePath: userPath),
      );
    }

    // 保存完成后重置下载状态，允许重新下载
    _updateDownloadInfo(const VideoDownloadInfo());

    return userPath ?? autoPath;
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

    // 取消下载并清理临时文件（不调用 setState）
    _disposeDownload();

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
    return ColoredBox(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? ValueListenableBuilder<BoxFit>(
              valueListenable: _videoFit,
              builder: (context, videoFit, _) {
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
                            downloadInfo: _downloadInfo,
                            onStartDownload: _startDownload,
                            onCancelDownload: _cancelDownload,
                            onSaveAs: _saveAs,
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
                            downloadInfo: _downloadInfo,
                            onStartDownload: _startDownload,
                            onCancelDownload: _cancelDownload,
                            onSaveAs: _saveAs,
                          );
                  },
                );
                return needsPadding
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: videoWidget,
                      )
                    : videoWidget;
              },
            )
          : const Center(
              child: VideoLoadingIndicator(
                size: 48,
                color: Colors.white,
              ),
            ),
    );
  }
}
