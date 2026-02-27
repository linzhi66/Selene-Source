import 'dart:ui';

/// 键盘错误处理器
///
/// 处理 Flutter 框架的已知键盘事件问题：
/// - 当使用 Alt+Tab 切换窗口时，可能会触发 HardwareKeyboard 断言错误
/// - 这是一个 Flutter 框架的已知问题，不影响应用功能
class KeyboardErrorHandler {
  KeyboardErrorHandler._();

  /// 初始化键盘错误处理
  ///
  /// 在 main() 函数的最开始调用，用于捕获并抑制键盘事件相关的断言错误
  static void initialize() {
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (_isKeyboardAssertionError(error)) {
        // 忽略键盘事件相关的断言错误
        return true;
      }
      return false;
    };
  }

  /// 判断是否为键盘事件相关的断言错误
  static bool _isKeyboardAssertionError(Object error) {
    if (error is! AssertionError) {
      return false;
    }
    final errorString = error.toString();
    return errorString.contains('KeyDownEvent') ||
        errorString.contains('KeyUpEvent') ||
        errorString.contains('_pressedKeys') ||
        errorString.contains('HardwareKeyboard');
  }
}
