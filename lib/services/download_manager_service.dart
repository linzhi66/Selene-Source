import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:encrypt/encrypt.dart' hide Key, IV;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:selene/models/download_task_record.dart';
import 'package:selene/services/download_storage_service.dart';

enum DownloadManagerStatus {
  idle,
  downloading,
  paused,
  completed,
  failed,
}

class DownloadProgressInfo {
  final String taskId;
  final DownloadManagerStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? errorMessage;
  final int? currentSegment;
  final int? totalSegments;

  const DownloadProgressInfo({
    required this.taskId,
    required this.status,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.currentSegment,
    this.totalSegments,
  });
}

class DownloadManagerService extends ChangeNotifier {
  static final DownloadManagerService _instance = DownloadManagerService._internal();
  factory DownloadManagerService() => _instance;
  DownloadManagerService._internal();

  final DownloadStorageService _storageService = DownloadStorageService();

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, StreamController<DownloadProgressInfo>> _progressControllers = {};
  final Map<String, bool> _taskLocks = {};

  late final Dio _dio = _createDio();

  static const int _maxConcurrentDownloads = 8;
  int _currentDownloads = 0;
  final List<String> _pendingQueue = [];

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _storageService.init();
    _isInitialized = true;

    await _resumePendingTasks();
  }

  Future<void> _resumePendingTasks() async {
    final tasks = _storageService.getDownloadingTasks();
    for (final task in tasks) {
      if (task.isPaused) {
        continue;
      }
      _pendingQueue.add(task.taskId);
    }
    _processQueue();
  }

  Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(request: false));
    }
    return dio;
  }

  String _generateTaskId(String url) {
    final hash = url.hashCode.abs().toRadixString(36);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '$hash$timestamp';
  }

  Future<Directory> _getDownloadDirectory() async {
    Directory? dir;
    try {
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final match = RegExp(r'^(/storage/emulated/\d+)').firstMatch(externalDir.path);
          if (match != null) {
            final storageRoot = match.group(1)!;
            dir = Directory('$storageRoot/Download');
          }
        }
        dir ??= await getDownloadsDirectory();
      } else if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        dir = await getDownloadsDirectory();
      }
    } catch (e) {
      debugPrint('获取下载目录失败: $e');
    }
    dir ??= await getApplicationDocumentsDirectory();
    final moonTVDir = Directory('${dir.path}/MoonTV');
    if (!moonTVDir.existsSync()) {
      await moonTVDir.create(recursive: true);
    }
    return moonTVDir;
  }

  Future<Directory> _getTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final downloadTempDir = Directory('${tempDir.path}/selene_downloads');
    if (!downloadTempDir.existsSync()) {
      await downloadTempDir.create(recursive: true);
    }
    return downloadTempDir;
  }

  Stream<DownloadProgressInfo>? getProgressStream(String taskId) {
    return _progressControllers[taskId]?.stream;
  }

  Future<DownloadTaskRecord?> createTask({
    required String url,
    required String fileName,
    Map<String, String>? headers,
    String? videoTitle,
    String? coverUrl,
    String? episodeInfo,
    String? source,
    String? sourceId,
  }) async {
    await init();

    final existingTask = _storageService.findTaskByUrl(url);
    if (existingTask != null && (existingTask.isDownloading || existingTask.isCompleted)) {
      return existingTask;
    }

    try {
      final taskId = _generateTaskId(url);
      final dir = await _getDownloadDirectory();
      final tempDir = await _getTempDirectory();

      String finalName = fileName;
      if (episodeInfo != null && episodeInfo.isNotEmpty) {
        final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.')) : '.mp4';
        final base = fileName.substring(
          0,
          fileName.lastIndexOf('.') > 0 ? fileName.lastIndexOf('.') : fileName.length,
        );
        finalName = '${base.trim()}-$episodeInfo$ext';
      }

      final filePath = '${dir.path}/$finalName';
      final tempFilePath = '${tempDir.path}/${taskId}_$finalName';
      final isM3u8 = url.toLowerCase().endsWith('.m3u8');

      final task = DownloadTaskRecord(
        taskId: taskId,
        url: url,
        fileName: finalName,
        filePath: filePath,
        tempFilePath: tempFilePath,
        isM3u8: isM3u8,
        headers: headers,
        videoTitle: videoTitle,
        coverUrl: coverUrl,
        episodeInfo: episodeInfo,
        source: source,
        sourceId: sourceId,
        status: 'pending',
      );

      await _storageService.saveTask(task);

      _progressControllers[taskId] = StreamController<DownloadProgressInfo>.broadcast();

      _pendingQueue.add(taskId);
      _processQueue();

      return task;
    } catch (e, st) {
      debugPrint('创建下载任务失败: $e\n$st');
      return null;
    }
  }

  void _processQueue() {
    while (_currentDownloads < _maxConcurrentDownloads && _pendingQueue.isNotEmpty) {
      final taskId = _pendingQueue.removeAt(0);
      final task = _storageService.getTask(taskId);
      if (task != null && !task.isCompleted) {
        _startDownloadInternal(taskId);
      }
    }
  }

  Future<void> _startDownloadInternal(String taskId) async {
    if (_taskLocks[taskId] == true) return;
    _taskLocks[taskId] = true;
    _currentDownloads++;

    try {
      final task = _storageService.getTask(taskId);
      if (task == null) return;

      await _storageService.updateTask(task.copyWith(status: 'downloading'));

      _emitProgress(taskId, DownloadProgressInfo(
        taskId: taskId,
        status: DownloadManagerStatus.downloading,
      ));

      if (task.isM3u8) {
        await _downloadM3u8(task);
      } else {
        await _downloadRegularFile(task);
      }
    } catch (e) {
      debugPrint('下载错误: $e');
      final task = _storageService.getTask(taskId);
      if (task != null && !task.isPaused) {
        await _storageService.markTaskFailed(taskId, e.toString());
        _emitProgress(taskId, DownloadProgressInfo(
          taskId: taskId,
          status: DownloadManagerStatus.failed,
          errorMessage: e.toString(),
        ));
      }
    } finally {
      _taskLocks.remove(taskId);
      _cancelTokens.remove(taskId);
      _currentDownloads--;
      _processQueue();
    }
  }

  void _emitProgress(String taskId, DownloadProgressInfo info) {
    final controller = _progressControllers[taskId];
    if (controller != null && !controller.isClosed) {
      controller.add(info);
    }
    notifyListeners();
  }

  Future<void> _downloadRegularFile(DownloadTaskRecord task) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.taskId] = cancelToken;

    int? totalBytes = task.totalBytes > 0 ? task.totalBytes : null;

    // 先获取文件总大小
    if (totalBytes == null) {
      try {
        final headRes = await _dio.head<dynamic>(task.url, options: Options(headers: task.headers));
        final contentLength = headRes.headers.value('content-length');
        final acceptRanges = headRes.headers.value('accept-ranges');

        if (contentLength != null) {
          totalBytes = int.tryParse(contentLength);
        }

        // 检查服务器是否支持分片下载
        if (acceptRanges != null && acceptRanges.toLowerCase() == 'bytes' && totalBytes != null && totalBytes > 10 * 1024 * 1024) {
          // 文件大于 10MB 且支持分片，使用多线程下载
          await _downloadWithChunks(task, totalBytes, cancelToken);
          return;
        }
      } catch (_) {}
    }

    // 不支持分片或小文件，使用单线程下载
    await _downloadSingleThread(task, cancelToken, totalBytes);
  }

  Future<void> _downloadWithChunks(DownloadTaskRecord task, int totalBytes, CancelToken mainCancelToken) async {
    const int chunkCount = 3;
    final chunkSize = (totalBytes / chunkCount).ceil();
    final chunks = <_DownloadChunk>[];

    // 创建分片信息
    for (var i = 0; i < chunkCount; i++) {
      final start = i * chunkSize;
      final end = (i == chunkCount - 1) ? totalBytes - 1 : start + chunkSize - 1;
      if (start >= totalBytes) break;

      chunks.add(_DownloadChunk(
        index: i,
        startByte: start,
        endByte: end,
        downloadedBytes: 0,
        tempPath: '${task.tempFilePath}.part$i',
        completed: false,
      ));
    }

    // 检查是否有已下载的分片
    for (final chunk in chunks) {
      final partFile = File(chunk.tempPath);
      if (partFile.existsSync()) {
        chunk.downloadedBytes = partFile.lengthSync();
        if (chunk.downloadedBytes >= chunk.size) {
          chunk.completed = true;
        }
      }
    }

    // 更新任务总大小
    await _storageService.updateTaskProgress(
      task.taskId,
      totalBytes: totalBytes,
      progress: chunks.fold<int>(0, (sum, c) => sum + c.downloadedBytes) / totalBytes,
    );

    final downloadedBytes = <int>[for (final c in chunks) c.downloadedBytes];
    var totalDownloaded = downloadedBytes.fold<int>(0, (sum, b) => sum + b);

    // 并发下载所有分片
    final futures = <Future<void>>[];
    for (final chunk in chunks) {
      if (chunk.completed) continue;

      futures.add(_downloadChunk(task, chunk, mainCancelToken, (downloaded) {
        downloadedBytes[chunk.index] = downloaded;
        totalDownloaded = downloadedBytes.fold<int>(0, (sum, b) => sum + b);
        final progress = totalDownloaded / totalBytes;

        _storageService.updateTaskProgress(
          task.taskId,
          downloadedBytes: totalDownloaded,
          totalBytes: totalBytes,
          progress: progress,
        );

        _emitProgress(task.taskId, DownloadProgressInfo(
          taskId: task.taskId,
          status: DownloadManagerStatus.downloading,
          progress: progress,
          downloadedBytes: totalDownloaded,
          totalBytes: totalBytes,
        ));
      }));
    }

    await Future.wait(futures);

    // 检查是否被取消
    if (mainCancelToken.isCancelled) {
      return;
    }

    // 合并分片
    await _mergeChunks(task, chunks, totalBytes);

    // 标记完成
    await _storageService.markTaskCompleted(task.taskId);
    _emitProgress(task.taskId, DownloadProgressInfo(
      taskId: task.taskId,
      status: DownloadManagerStatus.completed,
      progress: 1.0,
      downloadedBytes: totalBytes,
      totalBytes: totalBytes,
    ));
  }

  Future<void> _downloadChunk(
    DownloadTaskRecord task,
    _DownloadChunk chunk,
    CancelToken mainCancelToken,
    void Function(int downloaded) onProgress,
  ) async {
    final chunkCancelToken = CancelToken();
    _cancelTokens['${task.taskId}_chunk${chunk.index}'] = chunkCancelToken;

    final startByte = chunk.startByte + chunk.downloadedBytes;

    final opts = Options(
      headers: Map<String, String>.from(task.headers ?? {})
        ..['Range'] = 'bytes=$startByte-${chunk.endByte}',
      receiveTimeout: const Duration(minutes: 30),
    );

    try {
      await _dio.download(
        task.url,
        chunk.tempPath,
        options: opts,
        cancelToken: chunkCancelToken,
        deleteOnError: false,
        onReceiveProgress: (received, total) {
          if (mainCancelToken.isCancelled) {
            chunkCancelToken.cancel();
            return;
          }
          chunk.downloadedBytes = chunk.downloadedBytes + received;
          onProgress(chunk.downloadedBytes);
        },
      );
      chunk.completed = true;
    } finally {
      _cancelTokens.remove('${task.taskId}_chunk${chunk.index}');
    }
  }

  Future<void> _mergeChunks(DownloadTaskRecord task, List<_DownloadChunk> chunks, int totalBytes) async {
    final outputFile = File(task.tempFilePath);
    final sink = outputFile.openWrite();

    try {
      for (final chunk in chunks) {
        final partFile = File(chunk.tempPath);
        if (partFile.existsSync()) {
          await sink.addStream(partFile.openRead());
          await partFile.delete();
        }
      }
      await sink.close();
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  Future<void> _downloadSingleThread(DownloadTaskRecord task, CancelToken cancelToken, int? totalBytes) async {
    final tempFile = File(task.tempFilePath);
    int startByte = 0;

    if (tempFile.existsSync() && task.downloadedBytes > 0) {
      startByte = task.downloadedBytes;
    }

    final opts = Options(
      headers: Map<String, String>.from(task.headers ?? {}),
      receiveTimeout: const Duration(minutes: 30),
    );

    if (startByte > 0) {
      opts.headers?['Range'] = 'bytes=$startByte-';
    }

    if (totalBytes == null) {
      try {
        final headRes = await _dio.head<dynamic>(task.url, options: Options(headers: task.headers));
        final contentLength = headRes.headers.value('content-length');
        if (contentLength != null) {
          totalBytes = int.tryParse(contentLength);
        }
      } catch (_) {}
    }

    try {
      await _dio.download(
        task.url,
        task.tempFilePath,
        options: opts,
        cancelToken: cancelToken,
        deleteOnError: false,
        onReceiveProgress: (received, total) async {
          final actualReceived = startByte + received;
          final actualTotal = totalBytes ?? (startByte + received);
          final progress = actualTotal > 0 ? actualReceived / actualTotal : 0.0;

          await _storageService.updateTaskProgress(
            task.taskId,
            downloadedBytes: actualReceived,
            totalBytes: actualTotal,
            progress: progress,
          );

          _emitProgress(task.taskId, DownloadProgressInfo(
            taskId: task.taskId,
            status: DownloadManagerStatus.downloading,
            progress: progress,
            downloadedBytes: actualReceived,
            totalBytes: actualTotal,
          ));
        },
      );

      await _storageService.markTaskCompleted(task.taskId);
      _emitProgress(task.taskId, DownloadProgressInfo(
        taskId: task.taskId,
        status: DownloadManagerStatus.completed,
        progress: 1.0,
      ));
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _downloadM3u8(DownloadTaskRecord task) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.taskId] = cancelToken;

    final (segments, baseUrl) = await _resolveM3u8Playlist(task.url, task.headers, cancelToken);
    if (segments.isEmpty) {
      throw Exception('未找到 TS 片段');
    }

    final outputFile = File(task.tempFilePath);
    final startSegment = task.currentSegmentIndex ?? 0;

    if (startSegment == 0 && outputFile.existsSync()) {
      await outputFile.delete();
    }

    final sink = outputFile.openWrite(mode: startSegment > 0 ? FileMode.append : FileMode.write);
    final keyCache = <String, Uint8List>{};
    var totalBytes = task.downloadedBytes;

    try {
      for (var i = startSegment; i < segments.length; i++) {
        if (cancelToken.isCancelled) break;

        final currentTask = _storageService.getTask(task.taskId);
        if (currentTask == null || currentTask.isPaused) break;

        final seg = segments[i];
        Uint8List? segmentData;

        Uint8List? keyBytes;
        if (seg.keyUri != null) {
          if (!keyCache.containsKey(seg.keyUri!)) {
            final keyUrl = _resolveUrl(baseUrl, seg.keyUri!);
            final keyRes = await _dio.get<List<int>>(
              keyUrl,
              options: Options(responseType: ResponseType.bytes, headers: task.headers),
              cancelToken: cancelToken,
            );
            keyCache[seg.keyUri!] = Uint8List.fromList(keyRes.data!);
          }
          keyBytes = keyCache[seg.keyUri!];
        }

        final tsUrl = _resolveUrl(baseUrl, seg.url);
        final opts = Options(headers: Map<String, String>.from(task.headers ?? {}));

        if (seg.byteRangeLength != null) {
          final start = seg.byteRangeOffset ?? 0;
          final end = start + seg.byteRangeLength! - 1;
          opts.headers?['Range'] = 'bytes=$start-$end';
        }

        final tsRes = await _dio.get<List<int>>(
          tsUrl,
          options: opts..responseType = ResponseType.bytes,
          cancelToken: cancelToken,
        );
        segmentData = Uint8List.fromList(tsRes.data!);
        totalBytes += segmentData.length;

        if (keyBytes != null) {
          final iv = (seg.iv != null && seg.iv!.isNotEmpty)
              ? seg.iv!
              : _generateIvFromSequence(seg.sequenceNumber);
          segmentData = _decryptAes128Cbc(segmentData, keyBytes, iv);
        }

        sink.add(segmentData);

        final progress = (i + 1) / segments.length;
        await _storageService.updateTaskProgress(
          task.taskId,
          downloadedBytes: totalBytes,
          totalBytes: totalBytes,
          progress: progress,
          currentSegmentIndex: i + 1,
        );

        final taskRecord = _storageService.getTask(task.taskId);
        if (taskRecord != null) {
          await _storageService.updateTask(taskRecord.copyWith(totalSegments: segments.length));
        }

        _emitProgress(task.taskId, DownloadProgressInfo(
          taskId: task.taskId,
          status: DownloadManagerStatus.downloading,
          progress: progress,
          downloadedBytes: totalBytes,
          currentSegment: i + 1,
          totalSegments: segments.length,
        ));
      }

      await sink.close();

      if (!cancelToken.isCancelled) {
        final currentTask = _storageService.getTask(task.taskId);
        if (currentTask != null && !currentTask.isPaused) {
          await _storageService.markTaskCompleted(task.taskId);
          _emitProgress(task.taskId, DownloadProgressInfo(
            taskId: task.taskId,
            status: DownloadManagerStatus.completed,
            progress: 1.0,
            downloadedBytes: totalBytes,
          ));
        }
      }
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  Future<void> pauseTask(String taskId) async {
    _cancelTokens[taskId]?.cancel();
    await _storageService.markTaskPaused(taskId);
    _emitProgress(taskId, DownloadProgressInfo(
      taskId: taskId,
      status: DownloadManagerStatus.paused,
    ));
  }

  Future<void> resumeTask(String taskId) async {
    final task = _storageService.getTask(taskId);
    if (task == null || !task.canResume) return;

    await _storageService.markTaskPending(taskId);

    _pendingQueue.add(taskId);
    _processQueue();
  }

  Future<void> cancelTask(String taskId) async {
    _cancelTokens[taskId]?.cancel();

    final task = _storageService.getTask(taskId);
    if (task != null) {
      final tempFile = File(task.tempFilePath);
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }

    await _storageService.deleteTask(taskId);

    final controller = _progressControllers[taskId];
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _progressControllers.remove(taskId);

    notifyListeners();
  }

  Future<void> deleteTask(String taskId, {bool deleteFile = false}) async {
    await cancelTask(taskId);

    if (deleteFile) {
      final task = _storageService.getTask(taskId);
      if (task != null) {
        final file = File(task.filePath);
        if (file.existsSync()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<String?> saveToGallery(String taskId) async {
    final task = _storageService.getTask(taskId);
    if (task == null || !task.isCompleted) return null;

    final tempFile = File(task.tempFilePath);
    if (!tempFile.existsSync()) return null;

    try {
      final dir = await _getDownloadDirectory();
      var targetPath = '${dir.path}/${task.fileName}';
      var counter = 1;
      final ext = path.extension(task.fileName);
      final baseName = path.basenameWithoutExtension(task.fileName);

      while (File(targetPath).existsSync()) {
        targetPath = '${dir.path}/${baseName}_$counter$ext';
        counter++;
      }

      await tempFile.copy(targetPath);

      final updatedTask = task.copyWith(filePath: targetPath);
      await _storageService.updateTask(updatedTask);

      return targetPath;
    } catch (e) {
      debugPrint('保存文件失败: $e');
      return null;
    }
  }

  List<DownloadTaskRecord> getAllTasks() => _storageService.getAllTasks();
  DownloadTaskRecord? getTask(String taskId) => _storageService.getTask(taskId);
  DownloadTaskRecord? getTaskByUrl(String url) => _storageService.findTaskByUrl(url);
  List<DownloadTaskRecord> getDownloadingTasks() => _storageService.getDownloadingTasks();
  List<DownloadTaskRecord> getCompletedTasks() => _storageService.getCompletedTasks();
  List<DownloadTaskRecord> getFailedTasks() => _storageService.getFailedTasks();
  List<DownloadTaskRecord> getPausedTasks() => _storageService.getPausedTasks();

  int get downloadingCount => _storageService.downloadingCount;
  int get completedCount => _storageService.completedCount;
  int get failedCount => _storageService.failedCount;
  int get pausedCount => _storageService.pausedCount;

  Future<void> clearCompletedTasks() async {
    await _storageService.deleteCompletedTasks();
    notifyListeners();
  }

  Future<void> clearFailedTasks() async {
    await _storageService.deleteFailedTasks();
    notifyListeners();
  }

  Future<void> retryAllFailed() async {
    final failedTasks = getFailedTasks();
    for (final task in failedTasks) {
      await resumeTask(task.taskId);
    }
  }

  Future<void> pauseAll() async {
    final downloadingTasks = getDownloadingTasks();
    for (final task in downloadingTasks) {
      await pauseTask(task.taskId);
    }
  }

  Future<void> resumeAll() async {
    final pausedTasks = getPausedTasks();
    for (final task in pausedTasks) {
      await resumeTask(task.taskId);
    }
  }

  Future<(List<_HlsSegment>, String)> _resolveM3u8Playlist(
    String url,
    Map<String, String>? headers,
    CancelToken cancelToken,
  ) async {
    final res = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain, headers: headers),
      cancelToken: cancelToken,
    );
    final content = res.data!;
    final baseUrl = _getBaseUrl(url);

    if (content.contains('#EXT-X-STREAM-INF:')) {
      final subUrl = _selectHighestBitrateStream(content, baseUrl);
      if (subUrl.isEmpty) {
        throw Exception('主播放列表中未找到有效流');
      }
      return _resolveM3u8Playlist(subUrl, headers, cancelToken);
    }

    return (_parseMediaPlaylist(content, baseUrl), baseUrl);
  }

  String _selectHighestBitrateStream(String content, String baseUrl) {
    var bestUrl = '';
    var maxBandwidth = 0;
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        if (bwMatch != null) {
          final bw = int.parse(bwMatch.group(1)!);
          var j = i + 1;
          while (j < lines.length && (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
            j++;
          }
          if (j < lines.length && bw > maxBandwidth) {
            maxBandwidth = bw;
            bestUrl = _resolveUrl(baseUrl, lines[j].trim());
          }
        }
      }
    }
    return bestUrl;
  }

  List<_HlsSegment> _parseMediaPlaylist(String content, String baseUrl) {
    final segments = <_HlsSegment>[];
    String? currentKeyUri;
    Uint8List? currentIv;
    var currentDuration = 0;
    int? currentByteRangeLength;
    int? currentByteRangeOffset;
    var mediaSequence = 0;
    var segmentIndex = 0;

    final seqMatch = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(content);
    if (seqMatch != null) {
      mediaSequence = int.parse(seqMatch.group(1)!);
    }

    for (final line in content.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.isEmpty || trimmed.startsWith('#EXT-X-')) {
        if (trimmed.startsWith('#EXT-X-KEY:')) {
          if (trimmed.contains('METHOD=AES-128')) {
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
            final ivMatch = RegExp(r'IV=0x([0-9a-fA-F]+)').firstMatch(trimmed);
            currentKeyUri = uriMatch?.group(1);

            if (ivMatch != null) {
              final hex = ivMatch.group(1)!;
              if (hex.length == 32) {
                try {
                  final bytes = <int>[];
                  for (var i = 0; i < hex.length; i += 2) {
                    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
                  }
                  currentIv = Uint8List.fromList(bytes);
                } catch (_) {
                  currentIv = null;
                }
              } else {
                currentIv = null;
              }
            } else {
              currentIv = null;
            }
          } else {
            currentKeyUri = null;
            currentIv = null;
          }
          continue;
        }

        if (trimmed.startsWith('#EXT-X-BYTERANGE:')) {
          final match = RegExp(r'(\d+)(?:@(\d+))?').firstMatch(trimmed);
          if (match != null) {
            currentByteRangeLength = int.parse(match.group(1)!);
            currentByteRangeOffset = match.group(2) != null ? int.parse(match.group(2)!) : null;
          }
          continue;
        }

        if (trimmed.startsWith('#EXTINF:')) {
          currentDuration = (double.parse(trimmed.split(':')[1].split(',').first) * 1000).toInt();
          continue;
        }
      }

      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        final absUrl = _resolveUrl(baseUrl, trimmed);
        segments.add(_HlsSegment(
          url: absUrl,
          durationMs: currentDuration,
          byteRangeLength: currentByteRangeLength,
          byteRangeOffset: currentByteRangeOffset,
          keyUri: currentKeyUri,
          iv: currentIv,
          sequenceNumber: mediaSequence + segmentIndex,
        ));
        segmentIndex++;
        currentByteRangeLength = null;
        currentByteRangeOffset = null;
      }
    }
    return segments;
  }

  String _getBaseUrl(String url) {
    final uri = Uri.parse(url);
    final pathEnd = uri.path.lastIndexOf('/') + 1;
    return '${uri.scheme}://${uri.host}${uri.path.substring(0, pathEnd)}';
  }

  String _resolveUrl(String baseUrl, String relative) {
    final trimmed = relative.trim();
    if (trimmed.startsWith('http')) return trimmed;
    if (trimmed.startsWith('//')) {
      final scheme = Uri.parse(baseUrl).scheme;
      return '$scheme:$trimmed';
    }
    if (trimmed.startsWith('/')) {
      final baseUri = Uri.parse(baseUrl);
      return '${baseUri.scheme}://${baseUri.host}$trimmed';
    }
    return '$baseUrl$trimmed';
  }

  Uint8List _generateIvFromSequence(int sequence) {
    final iv = Uint8List(16);
    for (var i = 0; i < 12; i++) {
      iv[i] = 0;
    }
    iv[12] = (sequence >> 24) & 0xFF;
    iv[13] = (sequence >> 16) & 0xFF;
    iv[14] = (sequence >> 8) & 0xFF;
    iv[15] = sequence & 0xFF;
    return iv;
  }

  Uint8List _decryptAes128Cbc(Uint8List encrypted, Uint8List key, Uint8List iv) {
    if (key.length != 16 || iv.length != 16) {
      throw ArgumentError('AES-128 密钥和 IV 必须是 16 字节');
    }
    try {
      final ivParam = enc.IV(iv);
      final keyParam = enc.Key(key);
      final encrypter = Encrypter(AES(keyParam, mode: AESMode.cbc, padding: null));
      final encryptedData = Encrypted(encrypted);
      final decrypted = encrypter.decryptBytes(encryptedData, iv: ivParam);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      debugPrint('解密失败: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    for (final entry in _cancelTokens.entries) {
      entry.value.cancel();
    }
    for (final controller in _progressControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    super.dispose();
  }
}

class _HlsSegment {
  final String url;
  final int durationMs;
  final int? byteRangeLength;
  final int? byteRangeOffset;
  final String? keyUri;
  final Uint8List? iv;
  final int sequenceNumber;

  _HlsSegment({
    required this.url,
    required this.durationMs,
    this.byteRangeLength,
    this.byteRangeOffset,
    this.keyUri,
    this.iv,
    required this.sequenceNumber,
  });
}

class _DownloadChunk {
  final int index;
  final int startByte;
  final int endByte;
  int downloadedBytes;
  final String tempPath;
  bool completed;

  _DownloadChunk({
    required this.index,
    required this.startByte,
    required this.endByte,
    required this.downloadedBytes,
    required this.tempPath,
    required this.completed,
  });

  int get size => endByte - startByte + 1;
}
