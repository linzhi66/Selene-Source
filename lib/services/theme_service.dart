import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:macos_window_utils/macos_window_utils.dart';

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
  }

  // 更新 macOS 窗口外观
  void _updateMacOSWindowAppearance() async {
    if (!Platform.isMacOS) return;

    try {
      // 使用 WindowManipulator.overrideMacOSBrightness 来设置窗口外观
      if (isDarkMode) {
        await WindowManipulator.overrideMacOSBrightness(dark: true);
      } else {
        await WindowManipulator.overrideMacOSBrightness(dark: false);
      }
    } catch (e) {
      // 忽略错误，可能在某些环境下不支持
      debugPrint('Failed to update macOS window appearance: $e');
    }
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

  ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2c3e50),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFf8f9fa),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFffffff),
          foregroundColor: Color(0xFF2c3e50),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFFffffff),
          elevation: 2,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF2c3e50)),
          bodyMedium: TextStyle(color: Color(0xFF2c3e50)),
          bodySmall: TextStyle(color: Color(0xFF7f8c8d)),
          titleLarge: TextStyle(color: Color(0xFF2c3e50)),
          titleMedium: TextStyle(color: Color(0xFF2c3e50)),
          titleSmall: TextStyle(color: Color(0xFF2c3e50)),
        ),
      );

  ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2c3e50),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1e1e1e),
          foregroundColor: Color(0xFFffffff),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1e1e1e),
          elevation: 2,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFffffff)),
          bodyMedium: TextStyle(color: Color(0xFFffffff)),
          bodySmall: TextStyle(color: Color(0xFFb0b0b0)),
          titleLarge: TextStyle(color: Color(0xFFffffff)),
          titleMedium: TextStyle(color: Color(0xFFffffff)),
          titleSmall: TextStyle(color: Color(0xFFffffff)),
        ),
      );
}
