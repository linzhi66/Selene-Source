package io.flutter.selene

import android.content.pm.ActivityInfo
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 屏幕活动类
 * <p> 继承自 FlutterActivity, 用于配置 Flutter 引擎并处理屏幕方向控制逻辑
 * <p> 通过注册方法通道来接收来自 Dart 端的屏幕方向设置请求, 并根据请求调整当前 Activity 的屏幕方向
 * <p> 支持的屏幕方向设置方法如下:
 * <ul>
 *   <li><code>setPortraitLandscape</code> - 允许设备在竖屏和横屏之间自由旋转 </li>
 *   <li><code>setPortraitOnly</code> - 仅允许设备保持竖屏状态 </li>
 *   <li><code>setLandscapeOnly</code> - 仅允许设备保持横屏状态 </li>
 * </ul>
 *
 * @author 拒绝者
 * @date 2026.01.13
 */
class ScreenActivity : FlutterActivity() {
    /**
     * 屏幕方向通道常量定义
     * <p> 该对象用于定义 Flutter 应用中屏幕方向变更的通信通道标识符
     */
    companion object {
        private const val CHANNEL = "io.flutter.selene/orientation"
    }

    /**
     * 配置 Flutter 引擎并设置屏幕方向控制方法调用处理器
     * <p> 该方法用于配置 Flutter 引擎, 并注册一个方法调用处理器来处理来自 Dart 端的屏幕方向设置请求
     * <p> 支持的方法包括:
     * <ul>
     *   <li><code>setPortraitLandscape</code> - 允许竖屏和横屏 </li>
     *   <li><code>setPortraitOnly</code> - 仅请求竖屏 </li>
     *   <li><code>setLandscapeOnly</code> - 仅请求横屏 </li>
     * </ul>
     *
     * @param flutterEngine Flutter 引擎实例, 用于配置和注册方法通道
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setPortraitLandscape" -> {
                        // 请求竖屏和横屏
                        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR
                        result.success(null)
                    }

                    "setPortraitOnly" -> {
                        // 仅请求竖屏
                        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        result.success(null)
                    }

                    "setLandscapeOnly" -> {
                        // 仅请求横屏
                        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}