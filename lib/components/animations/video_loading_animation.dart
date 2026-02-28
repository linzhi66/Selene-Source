import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:selene/design/colors.dart';
import 'package:selene/utils/font_utils.dart';

/// 视频加载动画组件 - Design System 2026 风格
///
/// 特性：
/// - 流体波纹脉冲动画
/// - 玻璃态效果
/// - 霓虹光效
/// - 动态进度指示
class VideoLoadingAnimation extends StatefulWidget {
  final double progress;
  final String message;
  final String? emoji;
  final bool isDarkMode;
  final double size;

  const VideoLoadingAnimation({
    super.key,
    required this.progress,
    required this.message,
    this.emoji,
    required this.isDarkMode,
    this.size = 120,
  });

  @override
  State<VideoLoadingAnimation> createState() => _VideoLoadingAnimationState();
}

class _VideoLoadingAnimationState extends State<VideoLoadingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _waveController;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _waveController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppColors.primary;
    final secondaryColor = AppColors.secondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 主动画区域
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外层旋转光环
              AnimatedBuilder(
                animation: _rotateController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotateController.value * 2 * math.pi,
                    child: CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _OrbitalRingPainter(
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        progress: widget.progress,
                      ),
                    ),
                  );
                },
              ),

              // 中层脉冲波纹
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulseValue = _pulseController.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 波纹 1
                      _buildPulseRing(
                        delay: 0,
                        pulseValue: pulseValue,
                        color: primaryColor,
                      ),
                      // 波纹 2
                      _buildPulseRing(
                        delay: 0.33,
                        pulseValue: pulseValue,
                        color: secondaryColor,
                      ),
                      // 波纹 3
                      _buildPulseRing(
                        delay: 0.66,
                        pulseValue: pulseValue,
                        color: primaryColor.withValues(alpha: 0.5),
                      ),
                    ],
                  );
                },
              ),

              // 玻璃态中心容器
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  final glowIntensity = 0.5 + (_glowController.value * 0.5);
                  return Container(
                    width: widget.size * 0.55,
                    height: widget.size * 0.55,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primaryColor.withValues(alpha: 0.9 * glowIntensity),
                          secondaryColor.withValues(alpha: 0.8 * glowIntensity),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        // 霓虹光晕
                        BoxShadow(
                          color: primaryColor.withValues(
                              alpha: 0.4 * glowIntensity),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                        BoxShadow(
                          color: secondaryColor.withValues(
                              alpha: 0.3 * glowIntensity),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                        // 内阴影效果
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: widget.isDarkMode ? 0.3 : 0.1),
                          blurRadius: 10,
                          spreadRadius: -5,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.isDarkMode
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.2),
                          ),
                          child: Center(
                            child: widget.emoji != null
                                ? Text(
                                    widget.emoji!,
                                    style: const TextStyle(fontSize: 32),
                                  )
                                : AnimatedBuilder(
                                    animation: _waveController,
                                    builder: (context, child) {
                                      return CustomPaint(
                                        size: const Size(40, 30),
                                        painter: _WavePainter(
                                          progress: _waveController.value,
                                          color: Colors.white,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // 进度指示环
              SizedBox(
                width: widget.size * 0.7,
                height: widget.size * 0.7,
                child: CircularProgressIndicator(
                  value: widget.progress,
                  strokeWidth: 3,
                  backgroundColor:
                      (widget.isDarkMode ? Colors.white : Colors.black)
                          .withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    primaryColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // 流体进度条
        _buildFluidProgressBar(),

        const SizedBox(height: 20),

        // 加载文案
        _buildAnimatedText(),
      ],
    );
  }

  Widget _buildPulseRing({
    required double delay,
    required double pulseValue,
    required Color color,
  }) {
    final adjustedValue = (pulseValue + delay) % 1.0;
    final scale = 0.5 + (adjustedValue * 0.5);
    final opacity = (1.0 - adjustedValue) * 0.6;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size * 0.8,
        height: widget.size * 0.8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 2,
          ),
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity * 0.5),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFluidProgressBar() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Container(
          width: 220,
          height: 6,
          decoration: BoxDecoration(
            color: (widget.isDarkMode ? Colors.white : Colors.black)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Stack(
            children: [
              // 背景轨道
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // 流体进度
              FractionallySizedBox(
                widthFactor: widget.progress,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.secondary,
                        AppColors.primary,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CustomPaint(
                      painter: _FluidWavePainter(
                        progress: _waveController.value,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
              // 发光头部
              Positioned(
                left: widget.progress * 220 - 4,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.8),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnimatedText() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final fadeValue = 0.5 + (_pulseController.value * 0.5);
        return Text(
          widget.message,
          style: FontUtils.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: (widget.isDarkMode ? Colors.white : Colors.black87)
                .withValues(alpha: fadeValue),
          ),
        );
      },
    );
  }
}

/// 轨道光环绘制器
class _OrbitalRingPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final double progress;

  _OrbitalRingPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // 外环
    final outerPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, outerPaint);

    // 发光段
    final glowPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          primaryColor.withValues(alpha: 0.8),
          secondaryColor.withValues(alpha: 0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.5,
      false,
      glowPaint,
    );

    // 进度指示点
    if (progress > 0) {
      final dotAngle = progress * 2 * math.pi - math.pi / 2;
      final dotX = center.dx + math.cos(dotAngle) * radius;
      final dotY = center.dy + math.sin(dotAngle) * radius;

      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(dotX, dotY), 4, dotPaint);

      // 点光晕
      final glowDotPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(dotX, dotY), 8, glowDotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 波浪绘制器（中心图标）
class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _WavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    path.moveTo(0, centerY);

    for (var x = 0.0; x <= width; x += 2) {
      final normalizedX = x / width;
      final wave1 =
          math.sin((normalizedX * 4 * math.pi) + (progress * 2 * math.pi));
      final wave2 =
          math.sin((normalizedX * 2 * math.pi) - (progress * math.pi));
      final y = centerY + (wave1 * 5) + (wave2 * 3);
      path.lineTo(x, y);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 流体波浪绘制器（进度条）
class _FluidWavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _FluidWavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final width = size.width;
    final height = size.height;

    path.moveTo(0, height);

    for (var x = 0.0; x <= width; x += 2) {
      final normalizedX = x / width;
      final wave =
          math.sin((normalizedX * 6 * math.pi) + (progress * 2 * math.pi));
      final y = height / 2 + (wave * height / 4);
      path.lineTo(x, y);
    }

    path.lineTo(width, height);
    path.lineTo(0, height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 简化的视频加载指示器（用于小区域）
class VideoLoadingIndicator extends StatefulWidget {
  final double size;
  final Color? color;

  const VideoLoadingIndicator({
    super.key,
    this.size = 40,
    this.color,
  });

  @override
  State<VideoLoadingIndicator> createState() => _VideoLoadingIndicatorState();
}

class _VideoLoadingIndicatorState extends State<VideoLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 旋转外环
              RotationTransition(
                turns: _controller,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _IndicatorRingPainter(color: color),
                ),
              ),
              // 脉冲中心
              Container(
                width: widget.size * 0.4,
                height: widget.size * 0.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(
                    alpha: 0.3 + (_controller.value * 0.4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IndicatorRingPainter extends CustomPainter {
  final Color color;

  _IndicatorRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
