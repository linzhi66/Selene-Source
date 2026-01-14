import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// 原生方向控制服务
/// 用于通过原生 Android 代码更直接地控制屏幕方向
class OrientationService {
  static const platform = MethodChannel('io.flutter.selene/orientation');

  /// 请求竖屏和横屏
  static Future<void> setPortraitAndLandscape() async {
    try {
      await platform.invokeMethod('setPortraitLandscape');
    } on PlatformException catch (e) {
      debugPrint('[OrientationService] Failed to set portrait+landscape: $e');
    }
  }

  /// 仅请求竖屏
  static Future<void> setPortraitOnly() async {
    try {
      await platform.invokeMethod('setPortraitOnly');
    } on PlatformException catch (e) {
      debugPrint('[OrientationService] Failed to set portrait only: $e');
    }
  }

  /// 仅请求横屏
  static Future<void> setLandscapeOnly() async {
    try {
      await platform.invokeMethod('setLandscapeOnly');
    } on PlatformException catch (e) {
      debugPrint('[OrientationService] Failed to set landscape only: $e');
    }
  }
}
