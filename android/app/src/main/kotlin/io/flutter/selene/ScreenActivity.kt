package io.flutter.selene

import android.content.pm.ActivityInfo
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

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

    // 持有 MethodChannel 的引用，以便在 Activity 销毁时移除 handler，避免 native 在销毁后回调 Dart
    private var orientationChannel: MethodChannel? = null

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
        // 调用父类方法配置 Flutter 引擎
        super.configureFlutterEngine(flutterEngine)
        // 注册生成的插件
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        // 创建方法通道并设置方法调用处理器
        orientationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        // 设置方法调用处理器以响应来自 Dart 端的屏幕方向请求
        orientationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // 请求竖屏和横屏
                "setPortraitLandscape" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR
                    result.success(null)
                }
                // 仅请求竖屏
                "setPortraitOnly" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    result.success(null)
                }
                // 仅请求横屏
                "setLandscapeOnly" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    result.success(null)
                }
                // 未知方法调用
                else -> result.notImplemented()
            }
        }
    }

    // 在 Activity 销毁时清理资源，防止内存泄漏
    override fun onDestroy() {
        // 在 Activity 销毁时清除 handler，防止 native 端在 Activity 被回收后仍尝试回调 Dart
        try {
            orientationChannel?.setMethodCallHandler(null)
        } catch (e: Exception) {
            // Ignore failures during teardown
        }
        orientationChannel = null
        super.onDestroy()
    }
}