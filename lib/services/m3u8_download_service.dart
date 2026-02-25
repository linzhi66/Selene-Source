import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_task.dart';

class M3U8DownloadService extends ChangeNotifier {
  static final M3U8DownloadService _instance = M3U8DownloadService._internal();
  factory M3U8DownloadService() => _instance;
  M3U8DownloadService._internal();

  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, bool> _pausedTasks = {};
  
  List<DownloadTask> get tasks => _tasks.values.toList();
  List<DownloadTask> get downloadingTasks => 
      _tasks.values.where((t) => t.status == DownloadStatus.downloading).toList();
  List<DownloadTask> get completedTasks => 
      _tasks.values.where((t) => t.status == DownloadStatus.completed).toList();
  List<DownloadTask> get pendingTasks => 
      _tasks.values.where((t) => t.status == DownloadStatus.pending).toList();

  static const int _maxConcurrentDownloads = 10;
  static const int _maxConcurrentSegments = 5;
  int _currentDownloads = 0;

  Future<void> init() async {
    await _loadTasks();
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
    _dio.options.headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('download_tasks');
      if (tasksJson != null) {
        final List<dynamic> tasksList = json.decode(tasksJson);
        for (final taskJson in tasksList) {
          final task = DownloadTask.fromJson(taskJson);
          if (task.status == DownloadStatus.downloading) {
            task.status = DownloadStatus.paused;
          }
          _tasks[task.id] = task;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载下载任务失败: $e');
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = json.encode(_tasks.values.map((t) => t.toJson()).toList());
      await prefs.setString('download_tasks', tasksJson);
    } catch (e) {
      debugPrint('保存下载任务失败: $e');
    }
  }

  Future<String> get _downloadPath async {
    if (Platform.isAndroid) {
      final directory = Directory('/storage/emulated/0/Download/Selene');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${directory.path}/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir.path;
    } else if (Platform.isWindows) {
      final directory = Directory('${Platform.environment['USERPROFILE']}\\Downloads\\Selene');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } else if (Platform.isMacOS) {
      final directory = Directory('${Platform.environment['HOME']}/Downloads/Selene');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } else if (Platform.isLinux) {
      final directory = Directory('${Platform.environment['HOME']}/Downloads/Selene');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    }
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<DownloadTask?> createTask({
    required String url,
    required String title,
    required String episodeTitle,
    required String sourceName,
    required String cover,
    int episodeIndex = 0,
    int totalEpisodes = 1,
  }) async {
    try {
      final taskId = '${DateTime.now().millisecondsSinceEpoch}_${url.hashCode}';
      final downloadDir = await _downloadPath;
      final safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final safeEpisodeTitle = episodeTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final fileName = '${safeTitle}_$safeEpisodeTitle.mp4';
      final savePath = '$downloadDir/$fileName';

      final task = DownloadTask(
        id: taskId,
        url: url,
        title: title,
        episodeTitle: episodeTitle,
        sourceName: sourceName,
        cover: cover,
        savePath: savePath,
        totalSegments: 0,
        createdAt: DateTime.now(),
        episodeIndex: episodeIndex,
        totalEpisodes: totalEpisodes,
      );

      _tasks[taskId] = task;
      await _saveTasks();
      notifyListeners();

      return task;
    } catch (e) {
      debugPrint('创建下载任务失败: $e');
      return null;
    }
  }

  Future<void> startDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    if (_currentDownloads >= _maxConcurrentDownloads) {
      _updateTaskStatus(taskId, DownloadStatus.pending);
      return;
    }

    _currentDownloads++;
    _cancelTokens[taskId] = CancelToken();
    _pausedTasks[taskId] = false;
    _updateTaskStatus(taskId, DownloadStatus.downloading);

    try {
      final tempDir = await _getTempDir(taskId);
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      List<String> segmentUrls;
      int startIndex = task.downloadedSegments;

      if (startIndex == 0) {
        segmentUrls = await _parseM3U8(task.url, taskId);
        _updateTaskTotalSegments(taskId, segmentUrls.length);
      } else {
        segmentUrls = await _parseM3U8(task.url, taskId);
      }

      if (segmentUrls.isEmpty) {
        throw Exception('无法解析M3U8文件');
      }

      await _downloadSegments(
        taskId: taskId,
        segmentUrls: segmentUrls,
        tempDir: tempDir,
        startIndex: startIndex,
      );

      if (!_pausedTasks[taskId]! && !_cancelTokens[taskId]!.isCancelled) {
        await _mergeSegments(taskId, tempDir);
        _updateTaskStatus(taskId, DownloadStatus.completed, completedAt: DateTime.now());
        await _cleanupTempDir(tempDir);
      }
    } catch (e) {
      if (!_pausedTasks[taskId]! && !_cancelTokens[taskId]!.isCancelled) {
        _updateTaskStatus(taskId, DownloadStatus.failed, errorMessage: e.toString());
      }
    } finally {
      _currentDownloads--;
      _cancelTokens.remove(taskId);
      _processPendingTasks();
    }
  }

  Future<List<String>> _parseM3U8(String m3u8Url, String taskId) async {
    try {
      final response = await _dio.get(m3u8Url);
      final content = response.data as String;
      
      if (content.contains('#EXT-X-STREAM-INF:')) {
        final lines = content.split('\n');
        String? masterPlaylistUrl;
        int bestBandwidth = 0;
        
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
            final bandwidth = bandwidthMatch != null ? int.parse(bandwidthMatch.group(1)!) : 0;
            
            if (bandwidth > bestBandwidth && i + 1 < lines.length) {
              bestBandwidth = bandwidth;
              masterPlaylistUrl = lines[i + 1].trim();
            }
          }
        }
        
        if (masterPlaylistUrl != null) {
          final absoluteUrl = _resolveUrl(masterPlaylistUrl, m3u8Url);
          return await _parseM3U8(absoluteUrl, taskId);
        }
      }

      final lines = content.split('\n').map((line) => line.trim()).toList();
      final segments = <String>[];
      
      for (final line in lines) {
        if (line.startsWith('#EXT-X-KEY:')) {
          debugPrint('检测到加密的M3U8，可能无法正常下载');
        }
        if (!line.startsWith('#') && line.isNotEmpty) {
          final absoluteUrl = _resolveUrl(line, m3u8Url);
          segments.add(absoluteUrl);
        }
      }
      
      return segments;
    } catch (e) {
      debugPrint('解析M3U8失败: $e');
      return [];
    }
  }

  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    final baseUri = Uri.parse(baseUrl);
    if (url.startsWith('/')) {
      return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}$url';
    } else {
      final basePath = baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
      return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}$basePath$url';
    }
  }

  Future<void> _downloadSegments({
    required String taskId,
    required List<String> segmentUrls,
    required Directory tempDir,
    required int startIndex,
  }) async {
    final task = _tasks[taskId];
    if (task == null) return;

    final semaphore = <Completer<void>>[];
    final activeDownloads = <Future<void>>[];
    
    for (int i = startIndex; i < segmentUrls.length; i++) {
      if (_pausedTasks[taskId]! || _cancelTokens[taskId]?.isCancelled == true) {
        break;
      }

      while (activeDownloads.length >= _maxConcurrentSegments) {
        await Future.any(activeDownloads);
        activeDownloads.removeWhere((f) {
          return true;
        });
      }

      final segmentUrl = segmentUrls[i];
      final segmentPath = '${tempDir.path}/segment_${i.toString().padLeft(6, '0')}.ts';
      
      activeDownloads.add(_downloadSegment(
        taskId: taskId,
        segmentUrl: segmentUrl,
        segmentPath: segmentPath,
        segmentIndex: i,
      ));
    }

    await Future.wait(activeDownloads);
  }

  Future<void> _downloadSegment({
    required String taskId,
    required String segmentUrl,
    required String segmentPath,
    required int segmentIndex,
  }) async {
    if (_pausedTasks[taskId]! || _cancelTokens[taskId]?.isCancelled == true) {
      return;
    }

    try {
      await _dio.download(
        segmentUrl,
        segmentPath,
        cancelToken: _cancelTokens[taskId],
        options: Options(
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      
      final task = _tasks[taskId];
      if (task != null) {
        _updateTaskProgress(taskId, task.downloadedSegments + 1);
      }
    } catch (e) {
      if (!_cancelTokens[taskId]!.isCancelled) {
        debugPrint('下载片段 $segmentIndex 失败: $e');
        for (int retry = 0; retry < 3; retry++) {
          try {
            await _dio.download(
              segmentUrl,
              segmentPath,
              cancelToken: _cancelTokens[taskId],
              options: Options(
                receiveTimeout: const Duration(seconds: 30),
              ),
            );
            final task = _tasks[taskId];
            if (task != null) {
              _updateTaskProgress(taskId, task.downloadedSegments + 1);
            }
            return;
          } catch (_) {
            await Future.delayed(Duration(seconds: retry + 1));
          }
        }
      }
    }
  }

  Future<void> _mergeSegments(String taskId, Directory tempDir) async {
    final task = _tasks[taskId];
    if (task == null) return;

    final segments = await tempDir.list().toList();
    segments.sort((a, b) => a.path.compareTo(b.path));

    final outputFile = File(task.savePath);
    final sink = outputFile.openWrite();

    try {
      for (final segment in segments) {
        if (segment is File) {
          final bytes = await segment.readAsBytes();
          sink.add(bytes);
        }
      }
    } finally {
      await sink.close();
    }
  }

  Future<Directory> _getTempDir(String taskId) async {
    final downloadDir = await _downloadPath;
    return Directory('$downloadDir/.temp_$taskId');
  }

  Future<void> _cleanupTempDir(Directory tempDir) async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  void pauseDownload(String taskId) {
    _pausedTasks[taskId] = true;
    _cancelTokens[taskId]?.cancel('用户暂停');
    _updateTaskStatus(taskId, DownloadStatus.paused);
  }

  Future<void> resumeDownload(String taskId) async {
    _pausedTasks[taskId] = false;
    await startDownload(taskId);
  }

  void cancelDownload(String taskId) {
    _pausedTasks[taskId] = true;
    _cancelTokens[taskId]?.cancel('用户取消');
    _updateTaskStatus(taskId, DownloadStatus.cancelled);
  }

  Future<void> deleteTask(String taskId, {bool deleteFile = false}) async {
    final task = _tasks[taskId];
    if (task != null) {
      if (task.status == DownloadStatus.downloading) {
        cancelDownload(taskId);
      }

      if (deleteFile) {
        final file = File(task.savePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      final tempDir = await _getTempDir(taskId);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }

      _tasks.remove(taskId);
      await _saveTasks();
      notifyListeners();
    }
  }

  void _updateTaskStatus(String taskId, DownloadStatus status, {DateTime? completedAt, String? errorMessage}) {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = task.copyWith(
        status: status,
        completedAt: completedAt,
        errorMessage: errorMessage,
      );
      _saveTasks();
      notifyListeners();
    }
  }

  void _updateTaskProgress(String taskId, int downloadedSegments) {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = task.copyWith(downloadedSegments: downloadedSegments);
      notifyListeners();
    }
  }

  void _updateTaskTotalSegments(String taskId, int totalSegments) {
    final task = _tasks[taskId];
    if (task != null) {
      _tasks[taskId] = task.copyWith(totalSegments: totalSegments);
      _saveTasks();
      notifyListeners();
    }
  }

  void _processPendingTasks() {
    if (_currentDownloads < _maxConcurrentDownloads) {
      final pendingTask = pendingTasks.firstOrNull;
      if (pendingTask != null) {
        startDownload(pendingTask.id);
      }
    }
  }

  DownloadTask? getTask(String taskId) => _tasks[taskId];

  bool isTaskExists(String url) {
    return _tasks.values.any((t) => t.url == url && t.status != DownloadStatus.cancelled);
  }

  Future<void> startAllPending() async {
    for (final task in pendingTasks) {
      await startDownload(task.id);
    }
  }

  void pauseAllDownloading() {
    for (final task in downloadingTasks) {
      pauseDownload(task.id);
    }
  }

  Future<void> clearCompletedTasks() async {
    final completedTaskIds = completedTasks.map((t) => t.id).toList();
    for (final taskId in completedTaskIds) {
      _tasks.remove(taskId);
    }
    await _saveTasks();
    notifyListeners();
  }
}
