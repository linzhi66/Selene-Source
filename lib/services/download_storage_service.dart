import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:selene/models/download_task_record.dart';

class DownloadStorageService {
  static final DownloadStorageService _instance = DownloadStorageService._internal();
  factory DownloadStorageService() => _instance;
  DownloadStorageService._internal();

  static const String _boxName = 'download_tasks';
  Box<DownloadTaskRecord>? _box;

  final List<VoidCallback> _listeners = [];

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<DownloadTaskRecord>(_boxName);
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List<VoidCallback>.from(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('Listener error: $e');
      }
    }
  }

  Future<void> saveTask(DownloadTaskRecord task) async {
    await init();
    await _box!.put(task.taskId, task);
    _notifyListeners();
  }

  Future<void> updateTask(DownloadTaskRecord task) async {
    await saveTask(task);
  }

  Future<void> deleteTask(String taskId) async {
    await init();
    await _box!.delete(taskId);
    _notifyListeners();
  }

  Future<void> deleteCompletedTasks() async {
    await init();
    final keysToDelete = <dynamic>[];
    for (final key in _box!.keys) {
      final task = _box!.get(key);
      if (task != null && task.isCompleted) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await _box!.delete(key);
    }
    _notifyListeners();
  }

  Future<void> deleteFailedTasks() async {
    await init();
    final keysToDelete = <dynamic>[];
    for (final key in _box!.keys) {
      final task = _box!.get(key);
      if (task != null && task.isFailed) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await _box!.delete(key);
    }
    _notifyListeners();
  }

  Future<void> clearAllTasks() async {
    await init();
    await _box!.clear();
    _notifyListeners();
  }

  DownloadTaskRecord? getTask(String taskId) {
    if (_box == null || !_box!.isOpen) return null;
    return _box!.get(taskId);
  }

  List<DownloadTaskRecord> getAllTasks() {
    if (_box == null || !_box!.isOpen) return [];
    return _box!.values.toList();
  }

  List<DownloadTaskRecord> getDownloadingTasks() {
    return getAllTasks().where((t) => t.isDownloading || t.isPending).toList();
  }

  List<DownloadTaskRecord> getCompletedTasks() {
    return getAllTasks().where((t) => t.isCompleted).toList();
  }

  List<DownloadTaskRecord> getFailedTasks() {
    return getAllTasks().where((t) => t.isFailed).toList();
  }

  List<DownloadTaskRecord> getPausedTasks() {
    return getAllTasks().where((t) => t.isPaused).toList();
  }

  int get downloadingCount => getDownloadingTasks().length;
  int get completedCount => getCompletedTasks().length;
  int get failedCount => getFailedTasks().length;
  int get pausedCount => getPausedTasks().length;

  DownloadTaskRecord? findTaskByUrl(String url) {
    final tasks = getAllTasks();
    for (final task in tasks) {
      if (task.url == url) return task;
    }
    return null;
  }

  bool hasActiveTaskForUrl(String url) {
    final task = findTaskByUrl(url);
    return task != null && (task.isDownloading || task.isPending || task.isPaused);
  }

  Future<void> updateTaskProgress(
    String taskId, {
    int? downloadedBytes,
    int? totalBytes,
    double? progress,
    int? currentSegmentIndex,
  }) async {
    final task = getTask(taskId);
    if (task == null) return;

    final updatedTask = task.copyWith(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      progress: progress,
      currentSegmentIndex: currentSegmentIndex,
      status: 'downloading',
    );
    await saveTask(updatedTask);
  }

  Future<void> markTaskCompleted(String taskId, {String? filePath}) async {
    final task = getTask(taskId);
    if (task == null) return;

    final updatedTask = task.copyWith(
      status: 'completed',
      progress: 1.0,
      filePath: filePath,
    );
    await saveTask(updatedTask);
  }

  Future<void> markTaskFailed(String taskId, String errorMessage) async {
    final task = getTask(taskId);
    if (task == null) return;

    final updatedTask = task.copyWith(
      status: 'failed',
      errorMessage: errorMessage,
    );
    await saveTask(updatedTask);
  }

  Future<void> markTaskPaused(String taskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    final updatedTask = task.copyWith(status: 'paused');
    await saveTask(updatedTask);
  }

  Future<void> markTaskPending(String taskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    final updatedTask = task.copyWith(status: 'pending');
    await saveTask(updatedTask);
  }
}
