/// Design System 2026
library;

///
/// Selene 视频播放器的现代化设计系统
///
/// 设计理念：
/// - 玻璃拟态 + 霓虹光效
/// - 紫-粉-蓝科技渐变配色
/// - 流畅的微交互动画
/// - 清晰的视觉层次
/// - 多端一致的视觉体验
///
/// 使用示例：
/// ```dart
/// import 'package:selene/design/design_system.dart';
///
/// // 颜色
/// Container(
///   color: AppColors.primary,
///   decoration: BoxDecoration(
///     gradient: AppColors.primaryGradient,
///   ),
/// )
///
/// // 字体
/// Text('标题', style: AppTypography.headlineMediumStyle(isDark: true))
///
/// // 阴影
/// Container(
///   decoration: BoxDecoration(
///     boxShadow: AppShadows.medium,
///   ),
/// )
/// ```

// Design System 2026

export 'animations.dart';
export 'colors.dart';
export 'shadows.dart';
export 'typography.dart';
