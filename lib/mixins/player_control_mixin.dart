import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selene/services/page_cache_service.dart';

/// 播放器控制相关的通用功能 Mixin
///
/// 提供以下功能：
/// - 播放进度自动保存（带防抖）
/// - 进度节流控制
/// - 播放器状态管理
mixin PlayerControlMixin<T extends StatefulWidget> on State<T> {
  // ===== 进度保存相关 =====
  DateTime? _lastSaveTime;
  Timer? _saveDebounceTimer;

  /// 保存进度的时间间隔
  static const Duration saveProgressInterval = Duration(seconds: 10);

  /// 保存进度的防抖时间
  static const Duration saveDebounceDelay = Duration(seconds: 2);

  /// 是否正在保存中
  bool _isSaving = false;

  /// 带防抖的进度保存
  ///
  /// [force] - 是否强制立即保存，跳过防抖
  /// [scene] - 保存场景，用于调试
  /// [saveCallback] - 实际执行保存的回调函数
  void saveProgressWithDebounce({
    required bool force,
    required String scene,
    required VoidCallback saveCallback,
  }) {
    // 取消之前的防抖定时器
    _saveDebounceTimer?.cancel();

    if (force) {
      // 强制保存：立即执行
      _executeSave(scene, saveCallback);
      return;
    }

    // 检查时间间隔
    final now = DateTime.now();
    if (_lastSaveTime != null &&
        now.difference(_lastSaveTime!) < saveProgressInterval) {
      return; // 时间间隔不够，跳过保存
    }

    // 设置防抖定时器
    _saveDebounceTimer = Timer(saveDebounceDelay, () {
      if (mounted) {
        _executeSave(scene, saveCallback);
      }
    });
  }

  void _executeSave(String scene, VoidCallback saveCallback) {
    if (_isSaving) return;

    _isSaving = true;
    _lastSaveTime = DateTime.now();

    try {
      saveCallback();
    } catch (e) {
      debugPrint('保存进度失败 [场景: $scene]: $e');
    } finally {
      _isSaving = false;
    }
  }

  /// 立即取消待执行的保存任务
  void cancelPendingSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
  }

  // ===== 节流控制相关 =====
  DateTime? _lastUpdateTime;

  /// 检查是否需要更新 UI（节流）
  ///
  /// [interval] - 最小更新间隔
  bool shouldUpdateUI(Duration interval) {
    final now = DateTime.now();
    if (_lastUpdateTime == null ||
        now.difference(_lastUpdateTime!) > interval) {
      _lastUpdateTime = now;
      return true;
    }
    return false;
  }

  // ===== 播放器状态管理 =====
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    cancelPendingSave();
    super.dispose();
  }

  /// 检查是否已销毁
  bool get isDisposed => _isDisposed;

  /// 安全地执行 setState（仅在未销毁时执行）
  void safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  // ===== 播放记录工具方法 =====

  /// 获取播放记录
  Future<PlayRecord?> getPlayRecord(
    String source,
    String id,
    BuildContext context,
  ) async {
    try {
      final allPlayRecords = await PageCacheService().getPlayRecords(context);
      if (allPlayRecords.success && allPlayRecords.data != null) {
        final matchingRecords = allPlayRecords.data!.where(
          (record) => record.id == id && record.source == source,
        );
        if (matchingRecords.isNotEmpty) {
          return PlayRecord(
            index: matchingRecords.first.index,
            playTime: matchingRecords.first.playTime,
          );
        }
      }
    } catch (e) {
      debugPrint('获取播放记录失败: $e');
    }
    return null;
  }

  /// 检查是否应该恢复播放进度
  Future<bool> shouldResumeProgress() async {
    // 默认启用自动恢复
    return true;
  }
}

/// 播放记录数据类
class PlayRecord {
  final int index;
  final int playTime;

  PlayRecord({required this.index, required this.playTime});
}
