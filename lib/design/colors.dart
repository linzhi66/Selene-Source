import 'package:flutter/material.dart';

/// Design System 2026 - 颜色系统
/// 
/// 采用青绿-蓝色系现代配色，简洁专业
/// 深色模式：深邃暗色，浅色模式：清新明亮
class AppColors {
  AppColors._();

  // ==================== 主色调 ====================
  /// 主品牌色 - 青绿色
  static const Color primary = Color(0xFF14B8A6);
  
  /// 主品牌色 - 亮色版本
  static const Color primaryLight = Color(0xFF2DD4BF);
  
  /// 主品牌色 - 暗色版本
  static const Color primaryDark = Color(0xFF0D9488);

  /// 辅助色 - 天蓝色
  static const Color secondary = Color(0xFF3B82F6);
  
  /// 辅助色 - 亮色版本
  static const Color secondaryLight = Color(0xFF60A5FA);

  /// 强调色 - 珊瑚橙
  static const Color accent = Color(0xFFF97316);
  
  /// 强调色 - 亮色版本
  static const Color accentLight = Color(0xFFFB923C);

  /// 成功色 - 翠绿
  static const Color success = Color(0xFF22C55E);
  
  /// 成功色 - 亮色版本
  static const Color successLight = Color(0xFF4ADE80);

  /// 警告色 - 琥珀
  static const Color warning = Color(0xFFF59E0B);
  
  /// 警告色 - 亮色版本  
  static const Color warningLight = Color(0xFFFBBF24);

  /// 错误色 - 玫瑰红
  static const Color error = Color(0xFFEF4444);
  
  /// 错误色 - 亮色版本
  static const Color errorLight = Color(0xFFF87171);

  // ==================== 渐变定义 ====================
  /// 主渐变 - 青绿到天蓝
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  /// 科技渐变 - 青绿渐变
  static const LinearGradient techGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  /// 海洋渐变 - 蓝到青
  static const LinearGradient oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, primary],
  );

  /// 彩虹渐变
  static const LinearGradient rainbowGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primary, secondary, accent, success],
  );

  /// 深色背景渐变 - 深邃专业
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0A0F0E),
      Color(0xFF0F1412),
      Color(0xFF121917),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// 浅色背景渐变 - 清新明亮
  static const LinearGradient lightBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF0FDFA),
      Color(0xFFF8FAFC),
      Color(0xFFF1F5F9),
    ],
    stops: [0.0, 0.5, 1.0],
  );

  // ==================== 深色模式颜色 ====================
  /// 深色背景 - 主
  static const Color darkBackground = Color(0xFF0A0F0E);
  
  /// 深色背景 - 次
  static const Color darkSurface = Color(0xFF111816);
  
  /// 深色背景 - 三级
  static const Color darkElevated = Color(0xFF1A211F);
  
  /// 深色背景 - 卡片
  static const Color darkCard = Color(0xFF131B19);
  
  /// 深色文字 - 主
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  
  /// 深色文字 - 次
  static const Color darkTextSecondary = Color(0xFFA1A1AA);
  
  /// 深色文字 - 三级
  static const Color darkTextTertiary = Color(0xFF71717A);
  
  /// 深色边框
  static const Color darkBorder = Color(0xFF2A3532);

  // ==================== 浅色模式颜色 ====================
  /// 浅色背景 - 主
  static const Color lightBackground = Color(0xFFF8FAFC);
  
  /// 浅色背景 - 次
  static const Color lightSurface = Color(0xFFFFFFFF);
  
  /// 浅色背景 - 三级
  static const Color lightElevated = Color(0xFFF1F5F9);
  
  /// 浅色背景 - 卡片
  static const Color lightCard = Color(0xFFFFFFFF);
  
  /// 浅色文字 - 主
  static const Color lightTextPrimary = Color(0xFF0F172A);
  
  /// 浅色文字 - 次
  static const Color lightTextSecondary = Color(0xFF475569);
  
  /// 浅色文字 - 三级
  static const Color lightTextTertiary = Color(0xFF94A3B8);
  
  /// 浅色边框
  static const Color lightBorder = Color(0xFFE2E8F0);

  // ==================== 玻璃拟态颜色 ====================
  /// 深色玻璃背景
  static Color get darkGlass => const Color(0xFF111816).withValues(alpha: 0.75);
  
  /// 浅色玻璃背景
  static Color get lightGlass => const Color(0xFFFFFFFF).withValues(alpha: 0.75);
  
  /// 深色玻璃边框
  static Color get darkGlassBorder => const Color(0xFF2A3532).withValues(alpha: 0.3);
  
  /// 浅色玻璃边框
  static Color get lightGlassBorder => const Color(0xFFFFFFFF).withValues(alpha: 0.5);

  // ==================== 霓虹光效颜色 ====================
  /// 青绿霓虹光
  static Color get neonPrimary => primary.withValues(alpha: 0.5);
  
  /// 蓝色霓虹光
  static Color get neonSecondary => secondary.withValues(alpha: 0.5);
  
  /// 橙色霓虹光
  static Color get neonAccent => accent.withValues(alpha: 0.5);
  
  /// 绿色霓虹光
  static Color get neonGreen => success.withValues(alpha: 0.5);

  // ==================== 辅助方法 ====================
  /// 根据主题获取背景色
  static Color background(bool isDark) => 
      isDark ? darkBackground : lightBackground;
  
  /// 根据主题获取表面色
  static Color surface(bool isDark) => 
      isDark ? darkSurface : lightSurface;
  
  /// 根据主题获取卡片色
  static Color card(bool isDark) => 
      isDark ? darkCard : lightCard;
  
  /// 根据主题获取主文字色
  static Color textPrimary(bool isDark) => 
      isDark ? darkTextPrimary : lightTextPrimary;
  
  /// 根据主题获取次文字色
  static Color textSecondary(bool isDark) => 
      isDark ? darkTextSecondary : lightTextSecondary;
  
  /// 根据主题获取三级文字色
  static Color textTertiary(bool isDark) => 
      isDark ? darkTextTertiary : lightTextTertiary;
  
  /// 根据主题获取边框色
  static Color border(bool isDark) => 
      isDark ? darkBorder : lightBorder;
  
  /// 根据主题获取玻璃背景色
  static Color glassBackground(bool isDark) => 
      isDark ? darkGlass : lightGlass;
  
  /// 根据主题获取玻璃边框色
  static Color glassBorder(bool isDark) => 
      isDark ? darkGlassBorder : lightGlassBorder;

  /// 根据主题获取背景渐变
  static LinearGradient backgroundGradient(bool isDark) => 
      isDark ? darkBackgroundGradient : lightBackgroundGradient;
}

/// 颜色扩展方法
extension ColorExtensions on Color {
  /// 获取当前颜色的透明版本
  Color withOpacity(double opacity) => withValues(alpha: opacity);
  
  /// 混合两种颜色
  Color mix(Color other, double factor) {
    return Color.lerp(this, other, factor) ?? this;
  }
  
  /// 获取更亮的版本
  Color lighten([double factor = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness + factor).clamp(0.0, 1.0)).toColor();
  }
  
  /// 获取更暗的版本
  Color darken([double factor = 0.1]) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - factor).clamp(0.0, 1.0)).toColor();
  }
}
