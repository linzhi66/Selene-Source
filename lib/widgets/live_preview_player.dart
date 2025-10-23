import 'dart:async';
import 'package:flutter/material.dart';
import 'package:awesome_video_player/awesome_video_player.dart';
import '../models/live_channel.dart';

/// 直播频道预览组件
/// 优先显示 Logo，可选启用实时预览
class LivePreviewPlayer extends StatefulWidget {
  final LiveChannel channel;
  final Widget Function(BuildContext context) defaultBuilder;
  final bool enableLivePreview; // 是否启用实时预览

  const LivePreviewPlayer({
    super.key,
    required this.channel,
    required this.defaultBuilder,
    this.enableLivePreview = false, // 默认关闭实时预览
  });

  @override
  State<LivePreviewPlayer> createState() => _LivePreviewPlayerState();
}

class _LivePreviewPlayerState extends State<LivePreviewPlayer> {
  BetterPlayerController? _controller;
  bool _isInitialized = false;
  bool _showLogo = true;
  Timer? _initTimeout;

  @override
  void initState() {
    super.initState();
    // 只有启用实时预览且有视频源时才初始化播放器
    if (widget.enableLivePreview && widget.channel.uris.isNotEmpty) {
      // 延迟初始化，避免同时加载太多
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _initializePlayer();
        }
      });
    }
  }

  @override
  void dispose() {
    _initTimeout?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    try {
      final videoUrl = widget.channel.uris[0];
      
      // 设置5秒超时
      _initTimeout = Timer(const Duration(seconds: 5), () {
        if (mounted && !_isInitialized) {
          setState(() {
            _showLogo = true; // 超时后回退到 Logo
          });
          _controller?.dispose();
          _controller = null;
        }
      });
      
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        videoUrl,
        videoFormat: BetterPlayerVideoFormat.hls,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 500,
          maxBufferMs: 2000,
          bufferForPlaybackMs: 250,
          bufferForPlaybackAfterRebufferMs: 500,
        ),
        headers: widget.channel.headers,
      );

      final configuration = BetterPlayerConfiguration(
        autoPlay: true,
        looping: true,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
          enableMute: true,
          enableFullscreen: false,
          enablePip: false,
          enablePlayPause: false,
          enableProgressBar: false,
          enableSkips: false,
          enableSubtitles: false,
        ),
        aspectRatio: 16 / 9,
        fit: BoxFit.cover,
        autoDetectFullscreenAspectRatio: false,
        autoDetectFullscreenDeviceOrientation: false,
        allowedScreenSleep: true,
        errorBuilder: (context, errorMessage) {
          return _buildLogoOrDefault();
        },
      );

      _controller = BetterPlayerController(configuration);
      await _controller!.setupDataSource(dataSource);
      _controller!.setVolume(0);

      _controller!.addEventsListener((event) {
        if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
          _initTimeout?.cancel();
          if (mounted && !_isInitialized) {
            setState(() {
              _isInitialized = true;
              _showLogo = false;
            });
          }
        } else if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
          // 播放失败，回退到 Logo
          if (mounted) {
            setState(() {
              _showLogo = true;
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _showLogo = true;
        });
      }
    }
  }

  Widget _buildLogoOrDefault() {
    if (widget.channel.logo.isNotEmpty) {
      return Image.network(
        widget.channel.logo,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return widget.defaultBuilder(context);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return widget.defaultBuilder(context);
        },
      );
    }
    return widget.defaultBuilder(context);
  }

  @override
  Widget build(BuildContext context) {
    // 如果显示 Logo 或没有启用实时预览
    if (_showLogo || !widget.enableLivePreview || _controller == null) {
      return _buildLogoOrDefault();
    }

    // 显示实时预览
    return Stack(
      children: [
        Positioned.fill(
          child: BetterPlayer(controller: _controller!),
        ),
        // 加载中显示 Logo
        if (!_isInitialized)
          Positioned.fill(
            child: _buildLogoOrDefault(),
          ),
      ],
    );
  }
}
