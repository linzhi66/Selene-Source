import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../utils/device_utils.dart';

class LocalPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String episodeTitle;
  final String? cover;

  const LocalPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    required this.episodeTitle,
    this.cover,
  });

  @override
  State<LocalPlayerScreen> createState() => _LocalPlayerScreenState();
}

class _LocalPlayerScreenState extends State<LocalPlayerScreen>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking = false;
  double _volume = 100;
  bool _isMuted = false;
  bool _isFullscreen = false;
  bool _playerDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
    _hideControlsAfterDelay();
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) return;

    _player = Player();
    _videoController = VideoController(_player!);

    _player!.stream.position.listen((position) {
      if (!_isSeeking && mounted) {
        setState(() {
          _position = position;
        });
      }
    });

    _player!.stream.duration.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration;
        });
      }
    });

    _player!.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });

    try {
      await _player!.open(Media(widget.filePath), play: true);
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to open local video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法播放视频: $e')),
        );
      }
    }
  }

  void _hideControlsAfterDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (_isPlaying && mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls && _isPlaying) {
      _hideControlsAfterDelay();
    }
  }

  void _togglePlayPause() async {
    if (_player == null) return;
    if (_isPlaying) {
      await _player!.pause();
    } else {
      await _player!.play();
    }
  }

  void _seekTo(Duration position) async {
    if (_player == null) return;
    await _player!.seek(position);
    setState(() {
      _position = position;
    });
  }

  void _seekRelative(Duration offset) async {
    if (_player == null) return;
    final newPosition = _position + offset;
    if (newPosition < Duration.zero) {
      await _player!.seek(Duration.zero);
    } else if (newPosition > _duration) {
      await _player!.seek(_duration);
    } else {
      await _player!.seek(newPosition);
    }
  }

  void _toggleMute() async {
    if (_player == null) return;
    if (_isMuted) {
      await _player!.setVolume(_volume);
      setState(() {
        _isMuted = false;
      });
    } else {
      await _player!.setVolume(0);
      setState(() {
        _isMuted = true;
      });
    }
  }

  void _setVolume(double value) async {
    if (_player == null) return;
    await _player!.setVolume(value);
    setState(() {
      _volume = value;
      _isMuted = value == 0;
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isPlaying) {
      _player?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _playerDisposed = true;
    final player = _player;
    _player = null;
    _videoController = null;

    if (player != null) {
      Future.microtask(() async {
        try {
          await player.pause();
          await player.stop();
          await player.dispose();
        } catch (e) {
          debugPrint('Error disposing player: $e');
        }
      });
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _toggleControls,
            onDoubleTap: _togglePlayPause,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null) {
                if (details.primaryVelocity! > 0) {
                  _seekRelative(const Duration(seconds: -10));
                } else {
                  _seekRelative(const Duration(seconds: 10));
                }
              }
            },
            child: Container(
              color: Colors.black,
              child: Center(
                child: _isInitialized && _videoController != null
                    ? Video(
                        controller: _videoController!,
                        controls: null,
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),

          if (_showControls || !_isPlaying)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          if (_showControls || !_isPlaying)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.episodeTitle,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_showControls || !_isPlaying)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                  activeTrackColor: theme.primaryColor,
                                  inactiveTrackColor: Colors.white.withOpacity(0.3),
                                  thumbColor: theme.primaryColor,
                                  overlayColor: theme.primaryColor.withOpacity(0.3),
                                ),
                                child: Slider(
                                  value: _duration.inMilliseconds > 0
                                      ? _position.inMilliseconds.toDouble()
                                      : 0,
                                  min: 0,
                                  max: _duration.inMilliseconds.toDouble(),
                                  onChangeStart: (value) {
                                    setState(() {
                                      _isSeeking = true;
                                    });
                                  },
                                  onChanged: (value) {
                                    setState(() {
                                      _position = Duration(milliseconds: value.toInt());
                                    });
                                  },
                                  onChangeEnd: (value) {
                                    _seekTo(Duration(milliseconds: value.toInt()));
                                    setState(() {
                                      _isSeeking = false;
                                    });
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () => _seekRelative(const Duration(seconds: -10)),
                              icon: const Icon(Icons.replay_10, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 24),
                            GestureDetector(
                              onTap: _togglePlayPause,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: theme.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              onPressed: () => _seekRelative(const Duration(seconds: 10)),
                              icon: const Icon(Icons.forward_10, color: Colors.white, size: 28),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  onPressed: _toggleMute,
                                  icon: Icon(
                                    _isMuted ? Icons.volume_off : Icons.volume_up,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Slider(
                                    value: _isMuted ? 0 : _volume,
                                    min: 0,
                                    max: 100,
                                    onChanged: _setVolume,
                                    activeColor: theme.primaryColor,
                                    inactiveColor: Colors.white.withOpacity(0.3),
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: _toggleFullscreen,
                              icon: Icon(
                                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (!_isPlaying && _isInitialized)
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
