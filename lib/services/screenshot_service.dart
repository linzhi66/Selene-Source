import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 截图服务 - 全端统一保存截图到 Downloads/MoonTV
class ScreenshotService {
  /// 单例实例
  static final ScreenshotService _instance = ScreenshotService._internal();

  /// 获取单例
  factory ScreenshotService() => _instance;

  /// 内部构造函数
  ScreenshotService._internal();

  /// 获取下载目录 - 所有平台统一使用 Download/MoonTV
  Future<Directory> _getScreenshotDirectory() async {
    Directory? dir;
    try {
      if (Platform.isAndroid) {
        // Android: 尝试获取外部存储的 Download 目录
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          // /storage/emulated/0/Android/data/<package>/files
          // 需要返回到 /storage/emulated/0/Download
          final match =
              RegExp(r'^(/storage/emulated/\d+)').firstMatch(externalDir.path);
          if (match != null) {
            final storageRoot = match.group(1)!;
            dir = Directory('$storageRoot/Download');
          }
        }
        // 备选：使用 Downloads 目录
        dir ??= await getDownloadsDirectory();
      } else if (Platform.isIOS) {
        // iOS: 使用应用文档目录（iOS 沙盒限制，无法访问公共 Download）
        dir = await getApplicationDocumentsDirectory();
      } else {
        // Windows/macOS/Linux: 使用系统 Download 目录
        dir = await getDownloadsDirectory();
      }
    } catch (e) {
      debugPrint('Failed to get download directory: $e');
    }
    // 最终备选：应用文档目录
    dir ??= await getApplicationDocumentsDirectory();
    // 创建 MoonTV 子目录
    final moonTVDir = Directory('${dir.path}/MoonTV');
    if (!moonTVDir.existsSync()) {
      await moonTVDir.create(recursive: true);
    }
    return moonTVDir;
  }

  /// 生成截图文件名
  String _generateFileName() {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'screenshot_$timestamp.png';
  }

  /// 从 Player 截图
  ///
  /// 使用 media_kit 的 Player.screenshot() 方法获取当前视频帧
  Future<String?> captureScreenshot({
    required Player player,
    String? fileName,
  }) async {
    try {
      // 获取截图保存目录
      final targetDir = await _getScreenshotDirectory();
      // 构建文件名
      final finalFileName = fileName ?? _generateFileName();
      // 处理文件名冲突
      var targetPath = '${targetDir.path}/$finalFileName';
      var counter = 1;
      final ext = path.extension(finalFileName);
      final baseName = path.basenameWithoutExtension(finalFileName);
      while (File(targetPath).existsSync()) {
        targetPath = '${targetDir.path}/${baseName}_$counter$ext';
        counter++;
      }
      // 使用 media_kit 的 Player.screenshot() 方法截图
      final screenshotData = await player.screenshot();
      if (screenshotData == null) {
        debugPrint('Screenshot data is null');
        return null;
      }
      // 保存截图
      final file = File(targetPath);
      await file.writeAsBytes(screenshotData);
      debugPrint('Screenshot saved to: $targetPath');
      // Android/iOS: 同时保存到相册
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await Gal.putImage(targetPath);
          debugPrint('Screenshot also saved to gallery');
        } catch (e) {
          debugPrint('Failed to save to gallery: $e');
          // 相册保存失败不影响主流程
        }
      }
      return targetPath;
    } catch (e, st) {
      debugPrint('Screenshot capture failed: $e\n$st');
      return null;
    }
  }

  /// 通过 RenderRepaintBoundary 截图（备用方案）
  Future<String?> captureFromRenderObject({
    required RenderRepaintBoundary boundary,
    String? fileName,
  }) async {
    try {
      // 获取截图保存目录
      final targetDir = await _getScreenshotDirectory();
      // 构建文件名
      final finalFileName = fileName ?? _generateFileName();
      // 处理文件名冲突
      var targetPath = '${targetDir.path}/$finalFileName';
      var counter = 1;
      final ext = path.extension(finalFileName);
      final baseName = path.basenameWithoutExtension(finalFileName);
      while (File(targetPath).existsSync()) {
        targetPath = '${targetDir.path}/${baseName}_$counter$ext';
        counter++;
      }
      // 捕获图像
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('Failed to convert image to bytes');
        return null;
      }
      final pngBytes = byteData.buffer.asUint8List();
      // 保存截图
      final file = File(targetPath);
      await file.writeAsBytes(pngBytes);
      debugPrint('Screenshot saved to: $targetPath');
      // Android/iOS: 同时保存到相册
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await Gal.putImage(targetPath);
          debugPrint('Screenshot also saved to gallery');
        } catch (e) {
          debugPrint('Failed to save to gallery: $e');
        }
      }
      return targetPath;
    } catch (e, st) {
      debugPrint('Screenshot capture failed: $e\n$st');
      return null;
    }
  }
}
