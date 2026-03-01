import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:selene/design/colors.dart';
import 'package:selene/utils/font_utils.dart';

/// 现代化页面加载动画组件 - Design System 2026 风格
///
/// 适用于：
/// - 登录状态检查页面
/// - 页面首次加载
/// - 数据刷新等待
///
/// 特性：
/// - 多层波纹脉冲动画
/// - 霓虹光效呼吸灯
/// - 玻璃态中心容器
/// - 动态文字渐变
class ModernLoadingAnimation extends StatefulWidget {
  final String message;
  final String? subMessage;
  final bool isDarkMode;
  final double size;

  const ModernLoadingAnimation({
    super.key,
    required this.message,
    this.subMessage,
    required this.isDarkMode,
    this.size = 140,
  });

  @override
  State<ModernLoadingAnimation> createState() => _ModernLoadingAnimationState();
}

class _ModernLoadingAnimationState extends State<ModernLoadingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _glowController;
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 10000),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _glowController.dispose();
    _dotsController.dispose();
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
              // 外层旋转渐变环
              AnimatedBuilder(
                animation: _rotateController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotateController.value * 2 * math.pi,
                    child: CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _GradientOrbitalRingPainter(
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        isDarkMode: widget.isDarkMode,
                      ),
                    ),
                  );
                },
              ),

              // 多层脉冲波纹
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulseValue = _pulseController.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外层波纹
                      _buildPulseRing(
                        delay: 0,
                        pulseValue: pulseValue,
                        color: primaryColor,
                        maxSize: 0.95,
                      ),
                      // 中层波纹
                      _buildPulseRing(
                        delay: 0.25,
                        pulseValue: pulseValue,
                        color: secondaryColor,
                        maxSize: 0.85,
                      ),
                      // 内层波纹
                      _buildPulseRing(
                        delay: 0.5,
                        pulseValue: pulseValue,
                        color: primaryColor.withValues(alpha: 0.7),
                        maxSize: 0.75,
                      ),
                      // 额外波纹 - 增加层次感
                      _buildPulseRing(
                        delay: 0.75,
                        pulseValue: pulseValue,
                        color: secondaryColor.withValues(alpha: 0.5),
                        maxSize: 0.65,
                      ),
                    ],
                  );
                },
              ),

              // 玻璃态中心容器 - 带呼吸光效
              AnimatedBuilder(
                animation: _glowController,
                builder: (context, child) {
                  final glowIntensity = 0.6 + (_glowController.value * 0.4);
                  return Container(
                    width: widget.size * 0.5,
                    height: widget.size * 0.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primaryColor.withValues(alpha: 0.95 * glowIntensity),
                          secondaryColor.withValues(
                              alpha: 0.85 * glowIntensity),
                          primaryColor.withValues(alpha: 0.75 * glowIntensity),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        // 主霓虹光晕
                        BoxShadow(
                          color: primaryColor.withValues(
                            alpha: 0.5 * glowIntensity,
                          ),
                          blurRadius: 25,
                          spreadRadius: 8,
                        ),
                        // 次级光晕
                        BoxShadow(
                          color: secondaryColor.withValues(
                            alpha: 0.4 * glowIntensity,
                          ),
                          blurRadius: 35,
                          spreadRadius: 12,
                        ),
                        // 内阴影
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: widget.isDarkMode ? 0.4 : 0.15),
                          blurRadius: 15,
                          spreadRadius: -5,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.25),
                                Colors.white.withValues(alpha: 0.05),
                              ],
                            ),
                          ),
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                final scale =
                                    0.9 + (_pulseController.value * 0.1);
                                return Transform.scale(
                                  scale: scale,
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: widget.size * 0.25,
                                    color: Colors.white.withValues(alpha: 0.95),
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
            ],
          ),
        ),

        const SizedBox(height: 40),

        // 主文字 - 带动画效果
        _buildAnimatedText(),

        // 副文字（可选）
        if (widget.subMessage != null) ...[
          const SizedBox(height: 8),
          _buildSubText(),
        ],
      ],
    );
  }

  Widget _buildPulseRing({
    required double delay,
    required double pulseValue,
    required Color color,
    required double maxSize,
  }) {
    final adjustedValue = (pulseValue + delay) % 1.0;
    final scale = 0.3 + (adjustedValue * (maxSize - 0.3));
    final opacity = (1.0 - adjustedValue) * 0.5;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 1.5,
          ),
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity * 0.3),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedText() {
    return AnimatedBuilder(
      animation: _dotsController,
      builder: (context, child) {
        final dotCount = (_dotsController.value * 3).floor() + 1;
        final dots = '.' * dotCount;
        final fadeValue = 0.7 + (_pulseController.value * 0.3);

        return Text(
          '${widget.message}$dots',
          style: FontUtils.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: widget.isDarkMode
                ? Colors.white.withValues(alpha: fadeValue)
                : const Color(0xFF1e293b).withValues(alpha: fadeValue),
          ),
        );
      },
    );
  }

  Widget _buildSubText() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final fadeValue = 0.5 + (_glowController.value * 0.3);
        return Text(
          widget.subMessage!,
          style: FontUtils.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: widget.isDarkMode
                ? const Color(0xFF94a3b8).withValues(alpha: fadeValue)
                : const Color(0xFF64748b).withValues(alpha: fadeValue),
          ),
        );
      },
    );
  }
}

/// 渐变轨道光环绘制器
class _GradientOrbitalRingPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDarkMode;

  _GradientOrbitalRingPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // 背景细环
    final bgPaint = Paint()
      ..color =
          (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, radius, bgPaint);

    // 渐变发光段 - 主
    final glowPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          primaryColor.withValues(alpha: 0.9),
          secondaryColor.withValues(alpha: 0.9),
          primaryColor.withValues(alpha: 0.6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.8,
      false,
      glowPaint,
    );

    // 装饰点
    final dotAngle = math.pi / 4;
    final dotX = center.dx + math.cos(dotAngle) * radius;
    final dotY = center.dy + math.sin(dotAngle) * radius;

    // 点光晕
    final glowDotPaint = Paint()
      ..color = secondaryColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(dotX, dotY), 5, glowDotPaint);

    // 点核心
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(dotX, dotY), 2.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 简化版加载指示器（用于小区域或卡片内）
class ModernLoadingIndicator extends StatefulWidget {
  final double size;
  final Color? color;
  final bool isDarkMode;

  const ModernLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.isDarkMode = false,
  });

  @override
  State<ModernLoadingIndicator> createState() => _ModernLoadingIndicatorState();
}

class _ModernLoadingIndicatorState extends State<ModernLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
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
              // 旋转渐变环
              RotationTransition(
                turns: _controller,
                child: CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _ModernIndicatorRingPainter(
                    color: color,
                    isDarkMode: widget.isDarkMode,
                  ),
                ),
              ),
              // 脉冲中心
              Container(
                width: widget.size * 0.35,
                height: widget.size * 0.35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withValues(alpha: 0.6 + (_controller.value * 0.3)),
                      color.withValues(
                        alpha: 0.2 + ((1 - _controller.value) * 0.2),
                      ),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(
                        alpha: 0.3 + (_controller.value * 0.3),
                      ),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModernIndicatorRingPainter extends CustomPainter {
  final Color color;
  final bool isDarkMode;

  _ModernIndicatorRingPainter({
    required this.color,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // 背景环
    final bgPaint = Paint()
      ..color =
          (isDarkMode ? Colors.white : Colors.black).withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, bgPaint);

    // 渐变弧
    final paint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.8),
          color,
          color.withValues(alpha: 0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      math.pi * 1.5,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
