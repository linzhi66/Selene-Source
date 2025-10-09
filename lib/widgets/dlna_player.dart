import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dlna_dart/dlna.dart';
import 'package:dlna_dart/xmlParser.dart';
import 'dlna_player_controls.dart';

class DLNAPlayer extends StatefulWidget {
  final DLNADevice device;
  final double aspectRatio;
  final VoidCallback? onBackPressed;
  final VoidCallback? onNextEpisode;
  final bool isLastEpisode;
  final VoidCallback? onChangeDevice;
  final Duration? resumePosition;
  final Function(Duration)? onStopCasting;

  const DLNAPlayer({
    super.key,
    required this.device,
    this.aspectRatio = 16 / 9,
    this.onBackPressed,
    this.onNextEpisode,
    this.isLastEpisode = false,
    this.onChangeDevice,
    this.resumePosition,
    this.onStopCasting,
  });

  @override
  State<DLNAPlayer> createState() => _DLNAPlayerState();
}

class _DLNAPlayerState extends State<DLNAPlayer> {
  Timer? _statusTimer;
  PositionParser? position;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isLoading = true;
  Duration _resumePosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _resumePosition = widget.resumePosition ?? Duration.zero;
    _setPortraitOrientation();
    _startStatusPolling();
  }

  void _setPortraitOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
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

  void _startStatusPolling() {
    _statusTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _updateStatus();
    });
  }

  Future<void> _updateStatus() async {
    if (!mounted) return;

    try {
      // 获取播放位置
      final positionStr = await widget.device.position();
      final p = PositionParser(positionStr);

      position = p;
      _position = Duration(seconds: position?.RelTimeInt ?? 0);
      _duration = Duration(seconds: position?.TrackDurationInt ?? 0);

      final transportStr = await widget.device.getTransportInfo();
      final t = TransportInfoParser(transportStr);

      _isPlaying = t.CurrentTransportState == "PLAYING";

      // 如果获取到有效的 duration，则不再是加载状态
      if (_duration.inMilliseconds > 0) {
        _isLoading = false;

        // 不再是加载状态时，检查 resumePosition，如果不为 0 则跳转并清空
        if (_resumePosition.inSeconds > 0) {
          debugPrint('DLNA加载完成，跳转到恢复位置: ${_resumePosition.inSeconds}秒');
          _seekTo(_resumePosition);
          _resumePosition = Duration.zero; // 清空 resumePosition
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('获取DLNA状态失败: $e');
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      widget.device.pause();
      _isPlaying = false;
    } else {
      widget.device.play();
      _isPlaying = true;
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _stop() {
    widget.device.stop();
    // 通知父组件停止投屏，并传递当前播放位置
    widget.onStopCasting?.call(_position);
  }

  void _seekTo(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60);
    final seconds = position.inSeconds.remainder(60);
    final timeStr =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    widget.device.seek(timeStr);
  }

  void _setVolume(double volume) {
    final volumeInt = (volume * 100).round();
    widget.device.volume(volumeInt);
  }

  Duration get currentPosition => _position;

  @override
  void dispose() {
    _statusTimer?.cancel();
    _restoreOrientation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Container(
        color: Colors.black,
        child: DLNAPlayerControls(
          device: widget.device,
          position: _position,
          duration: _duration,
          isPlaying: _isPlaying,
          isLoading: _isLoading,
          onBackPressed: widget.onBackPressed,
          onNextEpisode: widget.onNextEpisode,
          isLastEpisode: widget.isLastEpisode,
          onPlayPause: _togglePlayPause,
          onStop: _stop,
          onSeek: _seekTo,
          onVolumeChange: _setVolume,
          onChangeDevice: widget.onChangeDevice,
        ),
      ),
    );
  }
}
