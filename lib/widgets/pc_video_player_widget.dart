import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'custom_media_kit_controls.dart';
import 'dlna_device_dialog.dart';

class PcVideoPlayerWidget extends StatefulWidget {
  final String? url;
  final VoidCallback? onBackPressed;
  final Function(PcVideoPlayerWidgetController)? onControllerCreated;
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
  final Function(bool isWebFullscreen)? onWebFullscreenChanged;

  const PcVideoPlayerWidget({
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
    this.onWebFullscreenChanged,
  });

  @override
  State<PcVideoPlayerWidget> createState() => _PcVideoPlayerWidgetState();
}

/// PcVideoPlayerWidget 的控制器，用于外部控制播放器
class PcVideoPlayerWidgetController {
  final _PcVideoPlayerWidgetState _state;

  PcVideoPlayerWidgetController._(this._state);

  /// 动态更新视频数据源
  Future<void> updateDataSource(String url, {Duration? startAt}) async {
    startAt ??= const Duration();
    await _state.updateDataSource(url, startAt: startAt);
  }

  /// 跳转到指定进度
  /// [position] 目标位置（秒）
  Future<void> seekTo(Duration position) async {
    await _state.seekTo(position);
  }

  /// 获取当前播放位置
  Duration? get currentPosition {
    return _state._player?.state.position;
  }

  /// 获取视频总时长
  Duration? get duration {
    return _state._player?.state.duration;
  }

  /// 获取播放状态
  bool get isPlaying {
    return _state._player?.state.playing ?? false;
  }

  /// 暂停播放
  void pause() {
    _state._player?.pause();
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
    _state._player?.dispose();
  }

  /// 退出网页全屏
  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }
}

class _PcVideoPlayerWidgetState extends State<PcVideoPlayerWidget>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  Player? _player;
  VideoController? _videoController;
  bool _hasCompleted = false;
  final List<VoidCallback> _progressListeners = [];
  double _cachedPlaybackSpeed = 1.0;
  String? _currentUrl;
  bool _isLoadingVideo = false; // 视频加载状态
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _completedSubscription;
  StreamSubscription? _durationSubscription;
  bool _shouldShowDLNAAfterExitFullscreen = false; // 退出全屏后是否显示 DLNA 对话框
  VoidCallback? _exitWebFullscreenCallback; // 用于退出网页全屏的回调

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.url != null) {
      _currentUrl = widget.url;
    }
    _initializePlayer();
    widget.onControllerCreated?.call(PcVideoPlayerWidgetController._(this));
  }

  Future<void> _initializePlayer({Duration? startAt}) async {
    if (!mounted) return;

    // 如果 _currentUrl 为 null 则停止初始化直接返回
    if (_currentUrl == null) return;

    // 创建播放器
    _player = Player();
    _videoController = VideoController(_player!);

    // 监听播放器事件
    _setupPlayerListeners();

    // 打开媒体
    await _player!.open(Media(_currentUrl!, start: startAt), play: true);

    setState(() {
      _isInitialized = true;
    });

    // 触发 ready 回调
    // widget.onReady?.call();
  }

  void _setupPlayerListeners() {
    if (_player == null) return;

    // 监听播放位置变化
    _positionSubscription = _player!.stream.position.listen((position) {
      if (!mounted) return;

      // 触发进度监听器
      for (final listener in _progressListeners) {
        try {
          listener();
        } catch (e) {
          debugPrint('Progress listener error: $e');
        }
      }
    });

    // 监听播放状态变化
    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (!mounted) return;
      // 可以在这里处理播放/暂停状态变化
    });

    // 监听播放完成
    _completedSubscription = _player!.stream.completed.listen((completed) {
      if (!mounted) return;
      if (completed && !_hasCompleted) {
        _hasCompleted = true;
        widget.onVideoCompleted?.call();
      }
    });

    // 监听加载完成
    _durationSubscription = _player!.stream.duration.listen((currentDuration) {
      if (!mounted) return;
      if (currentDuration == const Duration()) {
        return;
      }
      setState(() {
        _isLoadingVideo = false;
      });
      // 触发 ready 回调
      widget.onReady?.call();
    });
  }

  Future<void> updateDataSource(String url, {Duration? startAt}) async {
    if (!mounted) return;

    // 显示加载状态
    setState(() {
      _currentUrl = url;
      _isLoadingVideo = true;
    });

    // 如果播放器已经初始化完成则直接更换数据源
    if (_isInitialized && _player != null) {
      try {
        // 保存当前播放速度
        _cachedPlaybackSpeed = _player!.state.rate;

        // 打开新媒体
        await _player!.open(Media(url, start: startAt), play: true);

        // 恢复播放速度
        await _player!.setRate(_cachedPlaybackSpeed);

        setState(() {
          _hasCompleted = false;
        });
      } catch (e) {
        debugPrint('Error changing data source: $e');
      }
      // 触发 ready 回调
      // widget.onReady?.call();
      return;
    }

    // 如果没有初始化则直接调用 _initializePlayer 执行初始化
    await _initializePlayer(startAt: startAt);
  }

  Future<void> seekTo(Duration position) async {
    if (!mounted || _player == null) {
      return;
    }

    try {
      await _player!.seek(position);
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

  /// 退出网页全屏
  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressListeners.clear();
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Widget _buildPlayerContent() {
    return Container(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? Video(
              controller: _videoController!,
              controls: (state) {
                // 检查是否需要在退出全屏后显示 DLNA 对话框
                if (_shouldShowDLNAAfterExitFullscreen) {
                  try {
                    final isFullscreen = state.isFullscreen();
                    if (!isFullscreen) {
                      _shouldShowDLNAAfterExitFullscreen = false;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _showDLNADialog(state);
                        }
                      });
                    }
                  } catch (e) {
                    // 如果无法安全获取全屏状态，忽略错误
                  }
                }

                return CustomMediaKitControls(
                  state: state,
                  player: _player!,
                  onBackPressed: widget.onBackPressed,
                  onNextEpisode: widget.onNextEpisode,
                  onPause: widget.onPause,
                  playerController: PcVideoPlayerWidgetController._(this),
                  videoUrl: _currentUrl ?? '',
                  isLastEpisode: widget.isLastEpisode,
                  isLoadingVideo: _isLoadingVideo,
                  onCastStarted: widget.onCastStarted,
                  videoTitle: widget.videoTitle,
                  currentEpisodeIndex: widget.currentEpisodeIndex,
                  totalEpisodes: widget.totalEpisodes,
                  sourceName: widget.sourceName,
                  onDLNAButtonPressed: (isFullscreen) {
                    if (isFullscreen) {
                      // 如果在全屏状态，设置标记并退出全屏
                      setState(() {
                        _shouldShowDLNAAfterExitFullscreen = true;
                      });
                    }
                  },
                  onWebFullscreenChanged: widget.onWebFullscreenChanged,
                  onExitWebFullscreenCallbackReady: (callback) {
                    _exitWebFullscreenCallback = callback;
                  },
                );
              },
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }

  Future<void> _showDLNADialog(VideoState state) async {
    if (_player == null) return;

    final resumePos = _player!.state.position;

    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) => DLNADeviceDialog(
          currentUrl: _currentUrl ?? '',
          resumePosition: resumePos,
          videoTitle: widget.videoTitle,
          currentEpisodeIndex: widget.currentEpisodeIndex,
          totalEpisodes: widget.totalEpisodes,
          sourceName: widget.sourceName,
          onCastStarted: widget.onCastStarted,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildPlayerContent();
  }
}
