import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:selene/design/design_system.dart';

/// 主题服务
///
/// 管理应用的主题模式和颜色方案
/// 支持深色/浅色模式切换，并自动同步系统主题
class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    // 当为系统模式时，需要根据当前系统主题判断
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  ThemeService() {
    _loadTheme();
  }

  void _loadTheme() async {
    // 每次启动都默认跟随系统主题，不保存用户的手动选择
    _themeMode = ThemeMode.system;
    notifyListeners();
    _updateMacOSWindowAppearance();
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    // 不再保存到 SharedPreferences，每次启动都重新遵循系统主题
    notifyListeners();
    _updateMacOSWindowAppearance();

    // 更新系统 UI 样式
    _updateSystemUIOverlay();
  }

  // 更新 macOS 窗口外观
  void _updateMacOSWindowAppearance() async {
    if (!Platform.isMacOS) return;

    try {
      if (isDarkMode) {
        await WindowManipulator.overrideMacOSBrightness(dark: true);
      } else {
        await WindowManipulator.overrideMacOSBrightness(dark: false);
      }
    } catch (e) {
      debugPrint('Failed to update macOS window appearance: $e');
    }
  }

  // 更新系统 UI 覆盖样式
  void _updateSystemUIOverlay() {
    final brightness = isDarkMode ? Brightness.light : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness,
        statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            isDarkMode ? AppColors.darkBackground : AppColors.lightBackground,
        systemNavigationBarIconBrightness: brightness,
      ),
    );
  }

  void toggleTheme(BuildContext context) async {
    switch (_themeMode) {
      case ThemeMode.light:
        setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.system:
        // 当为系统模式时，检测当前系统主题并切换到相反模式
        final brightness = MediaQuery.of(context).platformBrightness;
        if (brightness == Brightness.light) {
          setThemeMode(ThemeMode.dark);
        } else {
          setThemeMode(ThemeMode.light);
        }
        break;
    }
  }

  /// 浅色主题
  ThemeData get lightTheme {
    final textTheme = _buildTextTheme(isDark: false);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryLight,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryLight,
        onSecondaryContainer: Colors.white,
        onSurface: AppColors.lightTextPrimary,
        surfaceContainerHighest: AppColors.lightElevated,
        onSurfaceVariant: AppColors.lightTextSecondary,
        error: AppColors.error,
        outline: AppColors.lightBorder,
        shadow: Colors.black,
      ),
      scaffoldBackgroundColor: AppColors.lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightSurface.withValues(alpha: 0.9),
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.headlineSmallStyle(),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.1),
      ),
      textTheme: textTheme,
      fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTypography.buttonStyle(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTypography.buttonStyle(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTypography.buttonStyle(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: AppTypography.bodyMediumStyle().copyWith(
          color: AppColors.lightTextTertiary,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface.withValues(alpha: 0.95),
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.lightTextTertiary,
        selectedLabelStyle: AppTypography.labelMediumStyle().copyWith(
          fontWeight: AppTypography.semiBold,
        ),
        unselectedLabelStyle: AppTypography.labelMediumStyle(),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightElevated,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: AppTypography.labelMediumStyle(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.lightTextPrimary.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppTypography.labelMediumStyle().copyWith(
          color: Colors.white,
        ),
      ),
    );
  }

  /// 深色主题
  ThemeData get darkTheme {
    final textTheme = _buildTextTheme(isDark: true);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryLight,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primary,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.secondaryLight,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondary,
        onSecondaryContainer: Colors.white,
        surface: AppColors.darkSurface,
        surfaceContainerHighest: AppColors.darkElevated,
        onSurfaceVariant: AppColors.darkTextSecondary,
        error: AppColors.errorLight,
        onError: Colors.white,
        outline: AppColors.darkBorder,
        shadow: Colors.black,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkSurface.withValues(alpha: 0.9),
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.headlineSmallStyle(isDark: true),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.3),
      ),
      textTheme: textTheme,
      fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTypography.buttonStyle(isDark: true),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTypography.buttonStyle(isDark: true),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTypography.buttonStyle(isDark: true),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorLight),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: AppTypography.bodyMediumStyle(isDark: true).copyWith(
          color: AppColors.darkTextTertiary,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface.withValues(alpha: 0.95),
        selectedItemColor: AppColors.primaryLight,
        unselectedItemColor: AppColors.darkTextTertiary,
        selectedLabelStyle:
            AppTypography.labelMediumStyle(isDark: true).copyWith(
          fontWeight: AppTypography.semiBold,
        ),
        unselectedLabelStyle: AppTypography.labelMediumStyle(isDark: true),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkElevated,
        selectedColor: AppColors.primary.withValues(alpha: 0.3),
        labelStyle: AppTypography.labelMediumStyle(isDark: true),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.darkTextPrimary.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: AppTypography.labelMediumStyle(isDark: true).copyWith(
          color: Colors.black,
        ),
      ),
    );
  }

  /// 构建文字主题
  TextTheme _buildTextTheme({required bool isDark}) => TextTheme(
        displayLarge: AppTypography.displayLargeStyle(isDark: isDark),
        displayMedium: AppTypography.displayMediumStyle(isDark: isDark),
        displaySmall: AppTypography.displaySmallStyle(isDark: isDark),
        headlineLarge: AppTypography.headlineLargeStyle(isDark: isDark),
        headlineMedium: AppTypography.headlineMediumStyle(isDark: isDark),
        headlineSmall: AppTypography.headlineSmallStyle(isDark: isDark),
        bodyLarge: AppTypography.bodyLargeStyle(isDark: isDark),
        bodyMedium: AppTypography.bodyMediumStyle(isDark: isDark),
        bodySmall: AppTypography.bodySmallStyle(isDark: isDark),
        labelLarge: AppTypography.labelLargeStyle(isDark: isDark),
        labelMedium: AppTypography.labelMediumStyle(isDark: isDark),
        labelSmall: AppTypography.labelSmallStyle(isDark: isDark),
      );
}
