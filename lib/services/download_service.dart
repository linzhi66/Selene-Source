import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:encrypt/encrypt.dart' hide Key, IV;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 下载任务状态枚举
enum DownloadStatus {
  waiting,
  downloading,
  paused,
  completed,
  failed,
}

/// 下载任务信息类
class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String filePath;
  final String tempFilePath;
  int totalBytes;
  int downloadedBytes;
  double progress;
  DownloadStatus status;
  String? errorMessage;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isM3u8;

  /// 构造函数
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.tempFilePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.status = DownloadStatus.waiting,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isM3u8 = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 从JSON创建DownloadTask实例
  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
        filePath: json['filePath'] as String,
        tempFilePath: json['tempFilePath'] as String? ?? '',
        totalBytes: json['totalBytes'] as int? ?? 0,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        status: DownloadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DownloadStatus.waiting,
        ),
        errorMessage: json['errorMessage'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isM3u8: json['isM3u8'] as bool? ?? false,
      );

  /// 转换DownloadTask实例为JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'filePath': filePath,
        'tempFilePath': tempFilePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'progress': progress,
        'status': status.name,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isM3u8': isM3u8,
      };

  /// 复制并更新DownloadTask实例
  DownloadTask copyWith({
    String? id,
    String? url,
    String? fileName,
    String? filePath,
    String? tempFilePath,
    int? totalBytes,
    int? downloadedBytes,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isM3u8,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isM3u8: isM3u8 ?? this.isM3u8,
    );
  }
}

/// HLS片段信息（含加密/字节范围）
class _HlsSegment {
  final String url;
  final int durationMs;
  final int? byteRangeLength;
  final int? byteRangeOffset;

  /// AES-128密钥URL
  final String? keyUri;

  /// 16字节IV（若无则用序列号生成）
  final Uint8List? iv;

  /// 媒体序列号（用于生成IV）
  final int sequenceNumber;

  /// 构造函数
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

/// 视频下载服务
class DownloadService {
  /// 单例实例
  static final DownloadService _instance = DownloadService._internal();

  /// 获取单例
  factory DownloadService() => _instance;

  /// 内部构造函数
  DownloadService._internal();

  late final Dio _dio = _createDio();

  /// 下载任务映射
  final Map<String, DownloadTask> _downloadTasks = {};

  /// 任务监听器映射
  final Map<String, List<ValueChanged<DownloadTask>>> _listeners = {};

  /// 取消令牌映射
  final Map<String, CancelToken> _cancelTokens = {};

  /// 内部锁对象
  final Map<String, bool> _taskLocks = {};

  /// 创建Dio实例
  Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: false,
      ));
    }
    return dio;
  }

  /// 生成唯一任务ID
  String _generateTaskId(String url) {
    final hash = url.hashCode.abs().toRadixString(36);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '$hash$timestamp';
  }

  /// 添加监听器
  void addListener(String taskId, ValueChanged<DownloadTask> listener) {
    final list = _listeners.putIfAbsent(
      taskId,
      () => <ValueChanged<DownloadTask>>[],
    );
    list.add(listener);
  }

  /// 移除监听器
  void removeListener(String taskId, ValueChanged<DownloadTask> listener) {
    final list = _listeners[taskId];
    if (list != null) {
      list.remove(listener);
      if (list.isEmpty) {
        _listeners.remove(taskId);
      }
    }
  }

  /// 通知监听器任务更新
  void _notifyListeners(String taskId, DownloadTask task) {
    final list = _listeners[taskId];
    if (list != null) {
      for (final listener in List<ValueChanged<DownloadTask>>.of(list)) {
        try {
          listener(task);
        } catch (e) {
          debugPrint('Listener error: $e');
        }
      }
    }
  }

  /// 获取临时目录
  Future<Directory> _getTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final downloadTempDir = Directory('${tempDir.path}/selene_downloads');
    if (!downloadTempDir.existsSync()) {
      await downloadTempDir.create(recursive: true);
    }
    return downloadTempDir;
  }

  /// 启动下载
  Future<DownloadTask?> startDownload({
    required String url,
    required String fileName,
    Map<String, String>? headers,
    String? episodeInfo,
  }) async {
    final taskId = _generateTaskId(url);

    // 检查是否已有相同URL的下载任务
    final existingTask = _findTaskByUrl(url);
    if (existingTask != null) {
      if (existingTask.status == DownloadStatus.downloading ||
          existingTask.status == DownloadStatus.completed) {
        return existingTask;
      }
    }

    try {
      final dir = await _getDownloadDirectory();
      final tempDir = await _getTempDirectory();

      // 构建最终文件名
      String finalName = fileName;
      if (episodeInfo != null && episodeInfo.isNotEmpty) {
        final ext = fileName.contains('.')
            ? fileName.substring(fileName.lastIndexOf('.'))
            : '.mp4';
        final base = fileName.substring(
          0,
          fileName.lastIndexOf('.') > 0
              ? fileName.lastIndexOf('.')
              : fileName.length,
        );
        finalName = '${base.trim()}-$episodeInfo$ext';
      }

      final filePath = '${dir.path}/$finalName';
      final tempFilePath = '${tempDir.path}/${taskId}_$finalName';
      final isM3u8 = url.toLowerCase().endsWith('.m3u8');

      final task = DownloadTask(
        id: taskId,
        url: url,
        fileName: finalName,
        filePath: filePath,
        tempFilePath: tempFilePath,
        isM3u8: isM3u8,
      );

      _downloadTasks[taskId] = task;
      final downloadingTask = task.copyWith(
        status: DownloadStatus.downloading,
      );
      _downloadTasks[taskId] = downloadingTask;
      _notifyListeners(taskId, downloadingTask);

      // 异步执行下载
      unawaited(_performDownload(taskId, headers: headers));

      return _downloadTasks[taskId];
    } catch (e, st) {
      debugPrint('Start download failed: $e\n$st');
      return null;
    }
  }

  /// 通过URL查找任务
  DownloadTask? _findTaskByUrl(String url) {
    for (final task in _downloadTasks.values) {
      if (task.url == url) {
        return task;
      }
    }
    return null;
  }

  /// 执行下载任务（支持M3U8和普通文件）
  Future<void> _performDownload(
    String taskId, {
    Map<String, String>? headers,
  }) async {
    // 使用锁防止重复执行
    if (_taskLocks[taskId] == true) {
      return;
    }
    _taskLocks[taskId] = true;
    try {
      final task = _downloadTasks[taskId];
      if (task == null || task.status != DownloadStatus.downloading) {
        return;
      }
      if (task.isM3u8) {
        await _downloadAndMergeM3u8(taskId, headers: headers);
      } else {
        await _downloadRegularFile(taskId, headers: headers);
      }
    } catch (e) {
      debugPrint('Download error: $e');
      final currentTask = _downloadTasks[taskId];
      if (currentTask != null &&
          currentTask.status == DownloadStatus.downloading) {
        final failedTask = currentTask.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        );
        _downloadTasks[taskId] = failedTask;
        _notifyListeners(taskId, failedTask);
      }
    } finally {
      _taskLocks.remove(taskId);
      _cancelTokens.remove(taskId);
    }
  }

  /// 下载普通文件
  Future<void> _downloadRegularFile(
    String taskId, {
    Map<String, String>? headers,
  }) async {
    final task = _downloadTasks[taskId];
    if (task == null) return;

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;
    // 获取文件大小
    final headRes = await _dio.head<dynamic>(
      task.url,
      options: Options(headers: headers),
    );
    final total = int.tryParse(
          headRes.headers.value('content-length') ?? '0',
        ) ??
        0;
    _updateTask(taskId, totalBytes: total);
    // 下载到临时文件
    await _dio.download(
      task.url,
      task.tempFilePath,
      options: Options(
        headers: headers,
        receiveTimeout: const Duration(minutes: 30),
      ),
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total <= 0) return;
        final progress = received / total;
        _updateProgress(taskId, progress, received);
      },
    );
    // 下载完成，标记为完成状态（但还在临时目录）
    await _finalizeDownload(taskId);
  }

  /// 下载并合并M3U8视频流
  Future<void> _downloadAndMergeM3u8(
    String taskId, {
    Map<String, String>? headers,
  }) async {
    final task = _downloadTasks[taskId];
    if (task == null) return;
    debugPrint('Starting M3U8 download: ${task.url}');
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;
    // sink 需要在 finally 中关闭
    IOSink? sink;
    try {
      // 1. 获取并解析M3U8（自动处理主列表→子列表）
      final (segments, baseUrl) = await _resolveM3u8Playlist(
        task.url,
        headers,
        cancelToken,
      );
      if (segments.isEmpty) {
        throw Exception('No TS segments found');
      }
      debugPrint('Found ${segments.length} TS segments');
      _updateProgress(taskId, 0, 0);
      // 2. 创建输出文件（清空旧文件）
      final outputFile = File(task.tempFilePath);
      if (outputFile.existsSync()) {
        await outputFile.delete();
      }
      sink = outputFile.openWrite();
      // 3. 密钥缓存 & 下载状态
      final keyCache = <String, Uint8List>{};
      var downloadedCount = 0;
      var totalBytes = 0;
      // 4. 流式处理每个片段
      for (var i = 0; i < segments.length; i++) {
        if (cancelToken.isCancelled) {
          throw DioException(
            type: DioExceptionType.cancel,
            requestOptions: RequestOptions(path: task.url),
          );
        }
        final currentTask = _downloadTasks[taskId];
        if (currentTask == null ||
            currentTask.status != DownloadStatus.downloading) {
          throw DioException(
            type: DioExceptionType.cancel,
            requestOptions: RequestOptions(path: task.url),
          );
        }
        final seg = segments[i];
        Uint8List? segmentData;
        // 4.1 下载密钥（如需）
        Uint8List? keyBytes;
        if (seg.keyUri != null) {
          if (!keyCache.containsKey(seg.keyUri!)) {
            final keyUrl = _resolveUrl(baseUrl, seg.keyUri!);
            final keyRes = await _dio.get<List<int>>(
              keyUrl,
              options: Options(
                responseType: ResponseType.bytes,
                headers: headers,
              ),
              cancelToken: cancelToken,
            );
            keyCache[seg.keyUri!] = Uint8List.fromList(keyRes.data!);
          }
          keyBytes = keyCache[seg.keyUri!];
        }
        // 4.2 构建TS请求（处理字节范围）
        final tsUrl = _resolveUrl(baseUrl, seg.url);
        final opts = Options(
          headers: Map<String, String>.from(headers ?? {}),
        );
        if (seg.byteRangeLength != null) {
          final start = seg.byteRangeOffset ?? 0;
          final end = start + seg.byteRangeLength! - 1;
          opts.headers?['Range'] = 'bytes=$start-$end';
        }
        // 4.3 下载TS片段
        final tsRes = await _dio.get<List<int>>(
          tsUrl,
          options: opts..responseType = ResponseType.bytes,
          cancelToken: cancelToken,
        );
        segmentData = Uint8List.fromList(tsRes.data!);
        totalBytes += segmentData.length;
        // 4.4 按需解密（AES-128 CBC 无填充）
        if (keyBytes != null) {
          // IV 可能为 null 或空列表，都需要生成
          final iv = (seg.iv != null && seg.iv!.isNotEmpty)
              ? seg.iv!
              : _generateIvFromSequence(seg.sequenceNumber);
          segmentData = _decryptAes128Cbc(segmentData, keyBytes, iv);
        }
        // 4.5 流式写入
        sink.add(segmentData);
        downloadedCount++;
        // 4.6 更新进度
        final progress = downloadedCount / segments.length;
        _updateProgress(taskId, progress, totalBytes);
      }

      await sink.close();
      sink = null;
      debugPrint('M3U8 merged successfully');

      // 下载完成
      await _finalizeDownload(taskId);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('M3U8 download canceled');
      }
      rethrow;
    } finally {
      // 确保 sink 被关闭
      if (sink != null) {
        try {
          await sink.close();
          debugPrint('M3U8 sink closed');
        } catch (e) {
          debugPrint('Failed to close sink: $e');
        }
      }
    }
  }

  /// 递归解析M3U8（主列表→最高码率子列表→媒体列表）
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

    // 检查是否为主列表（含#EXT-X-STREAM-INF）
    if (content.contains('#EXT-X-STREAM-INF:')) {
      debugPrint('Detected master playlist, selecting highest bitrate...');
      final subUrl = _selectHighestBitrateStream(content, baseUrl);
      if (subUrl.isEmpty) {
        throw Exception('No valid stream found in master playlist');
      }
      return _resolveM3u8Playlist(subUrl, headers, cancelToken);
    }

    // 解析媒体列表
    return (_parseMediaPlaylist(content, baseUrl), baseUrl);
  }

  /// 从主列表选择最高码率流
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
          // 找下一行非注释行
          var j = i + 1;
          while (j < lines.length &&
              (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
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

  /// 解析媒体列表（含加密/字节范围/序列号）
  List<_HlsSegment> _parseMediaPlaylist(String content, String baseUrl) {
    final segments = <_HlsSegment>[];
    String? currentKeyUri;
    Uint8List? currentIv;
    var currentDuration = 0;
    int? currentByteRangeLength;
    int? currentByteRangeOffset;
    // 起始序列号
    var mediaSequence = 0;
    // 当前片段在列表中的索引
    var segmentIndex = 0;
    // 提取起始序列号（如有）
    final seqMatch = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(content);
    if (seqMatch != null) {
      mediaSequence = int.parse(seqMatch.group(1)!);
    }
    // 解析每行
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#EXT-X-')) {
        // 处理加密标签
        if (trimmed.startsWith('#EXT-X-KEY:')) {
          if (trimmed.contains('METHOD=AES-128')) {
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
            final ivMatch = RegExp(r'IV=0x([0-9a-fA-F]+)').firstMatch(trimmed);
            currentKeyUri = uriMatch?.group(1);
            if (ivMatch != null) {
              final hex = ivMatch.group(1)!;
              // 确保 hex 是有效的 32 字符（16字节）
              if (hex.length == 32) {
                try {
                  final bytes = <int>[];
                  for (var i = 0; i < hex.length; i += 2) {
                    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
                  }
                  currentIv = Uint8List.fromList(bytes);
                } catch (e) {
                  debugPrint('Failed to parse IV hex: $hex, error: $e');
                  currentIv = null;
                }
              } else {
                // IV 格式不正确，使用序列号生成
                debugPrint('Invalid IV format: $hex, using sequence number');
                currentIv = null;
              }
            } else {
              // 后续用序列号生成
              currentIv = null;
            }
          } else {
            currentKeyUri = null;
            currentIv = null;
          }
          continue;
        }
        // 处理字节范围
        if (trimmed.startsWith('#EXT-X-BYTERANGE:')) {
          final match = RegExp(r'(\d+)(?:@(\d+))?').firstMatch(trimmed);
          if (match != null) {
            currentByteRangeLength = int.parse(match.group(1)!);
            currentByteRangeOffset =
                match.group(2) != null ? int.parse(match.group(2)!) : null;
          }
          continue;
        }
        // 提取片段时长
        if (trimmed.startsWith('#EXTINF:')) {
          currentDuration =
              (double.parse(trimmed.split(':')[1].split(',').first) * 1000)
                  .toInt();
          continue;
        }
      }
      // 提取TS URL（非注释非空行）
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        final absUrl = _resolveUrl(baseUrl, trimmed);
        segments.add(
          _HlsSegment(
            url: absUrl,
            durationMs: currentDuration,
            byteRangeLength: currentByteRangeLength,
            byteRangeOffset: currentByteRangeOffset,
            keyUri: currentKeyUri,
            iv: currentIv,
            sequenceNumber: mediaSequence + segmentIndex,
          ),
        );
        segmentIndex++;
        // 重置字节范围（仅作用于下一个片段）
        currentByteRangeLength = null;
        currentByteRangeOffset = null;
      }
    }
    return segments;
  }

  /// 提取基础URL（用于相对路径解析）
  String _getBaseUrl(String url) {
    final uri = Uri.parse(url);
    final pathEnd = uri.path.lastIndexOf('/') + 1;
    return '${uri.scheme}://${uri.host}${uri.path.substring(0, pathEnd)}';
  }

  /// 解析相对URL为绝对URL
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

  /// 生成HLS标准IV（16字节大端序列号）
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

  /// AES-128 CBC 无填充解密（HLS标准）
  Uint8List _decryptAes128Cbc(
    Uint8List encrypted,
    Uint8List key,
    Uint8List iv,
  ) {
    if (key.length != 16 || iv.length != 16) {
      throw ArgumentError(
        'Key and IV must be 16 bytes for AES-128, got key=${key.length}, iv=${iv.length}',
      );
    }
    try {
      final ivParam = enc.IV(iv);
      final keyParam = enc.Key(key);
      final encrypter = Encrypter(
        AES(keyParam, mode: AESMode.cbc, padding: null),
      );
      final encryptedData = Encrypted(encrypted);
      // 使用 decryptBytes 直接获取二进制数据，而不是 decrypt 转为字符串
      final decrypted = encrypter.decryptBytes(encryptedData, iv: ivParam);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      debugPrint(
          'Decryption failed (encrypted length: ${encrypted.length}): $e');
      rethrow;
    }
  }

  /// 更新任务
  void _updateTask(
    String taskId, {
    int? totalBytes,
    int? downloadedBytes,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
  }) {
    final task = _downloadTasks[taskId];
    if (task == null) return;
    final updated = task.copyWith(
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      progress: progress,
      status: status,
      errorMessage: errorMessage,
    );
    _downloadTasks[taskId] = updated;
    _notifyListeners(taskId, updated);
  }

  /// 更新下载进度
  void _updateProgress(String taskId, double progress, int bytes) {
    final task = _downloadTasks[taskId];
    if (task == null || task.status != DownloadStatus.downloading) return;
    final updated = task.copyWith(
      progress: progress.clamp(0.0, 1.0),
      downloadedBytes: bytes,
    );
    _downloadTasks[taskId] = updated;
    _notifyListeners(taskId, updated);
  }

  /// 完成下载（移动到目标位置）
  Future<void> _finalizeDownload(String taskId) async {
    final task = _downloadTasks[taskId];
    if (task == null) return;
    final tempFile = File(task.tempFilePath);
    if (!tempFile.existsSync()) {
      throw Exception('Temp file not found');
    }
    // 获取文件大小
    final fileSize = await tempFile.length();
    final completedTask = task.copyWith(
      status: DownloadStatus.completed,
      downloadedBytes: fileSize,
      progress: 1.0,
    );
    _downloadTasks[taskId] = completedTask;
    _notifyListeners(taskId, completedTask);
    debugPrint('Download completed: ${task.fileName}');
  }

  /// 另存为 - 保存到 Download/MoonTV 目录
  Future<String?> saveAs(String taskId) async {
    final task = _downloadTasks[taskId];
    if (task == null) return null;
    final tempFile = File(task.tempFilePath);
    if (!tempFile.existsSync()) {
      debugPrint('Temp file not found: ${task.tempFilePath}');
      return null;
    }
    try {
      // 所有平台统一保存到 Download/MoonTV
      return await _saveToDownloadDirectory(taskId, task, tempFile);
    } catch (e) {
      debugPrint('Save as failed: $e');
      return null;
    }
  }

  /// 保存到 Download/MoonTV 目录（所有平台统一）
  Future<String?> _saveToDownloadDirectory(
    String taskId,
    DownloadTask task,
    File tempFile,
  ) async {
    try {
      // 检查文件是否存在
      if (!tempFile.existsSync()) {
        throw Exception('临时文件不存在: ${tempFile.path}');
      }
      final fileSize = await tempFile.length();
      debugPrint('Saving video to Download/MoonTV, file size: $fileSize bytes');
      // 获取 Download/MoonTV 目录
      final targetDir = await _getDownloadDirectory();
      // 构建目标路径，处理文件名冲突
      var targetPath = '${targetDir.path}/${task.fileName}';
      var counter = 1;
      final ext = path.extension(task.fileName);
      final baseName = path.basenameWithoutExtension(task.fileName);
      while (File(targetPath).existsSync()) {
        targetPath = '${targetDir.path}/${baseName}_$counter$ext';
        counter++;
      }
      // 复制文件到目标位置
      await tempFile.copy(targetPath);
      debugPrint('Video saved to: $targetPath');
      // 更新任务路径
      final updatedTask = task.copyWith(filePath: targetPath);
      _downloadTasks[taskId] = updatedTask;
      _notifyListeners(taskId, updatedTask);
      return targetPath;
    } catch (e) {
      debugPrint('Failed to save video to Download/MoonTV: $e');
      // 如果保存失败，尝试保存到应用目录作为备选
      return _saveToAppDirectory(taskId, task, tempFile);
    }
  }

  /// 保存到应用目录（备用方案）
  Future<String?> _saveToAppDirectory(
    String taskId,
    DownloadTask task,
    File tempFile,
  ) async {
    try {
      final targetDir = await _getDownloadDirectory();
      // 构建目标路径
      var targetPath = '${targetDir.path}/${task.fileName}';
      var counter = 1;
      final ext = path.extension(task.fileName);
      final baseName = path.basenameWithoutExtension(task.fileName);
      while (File(targetPath).existsSync()) {
        targetPath = '${targetDir.path}/${baseName}_$counter$ext';
        counter++;
      }
      // 复制文件
      await tempFile.copy(targetPath);
      // 更新任务路径
      final updatedTask = task.copyWith(filePath: targetPath);
      _downloadTasks[taskId] = updatedTask;
      _notifyListeners(taskId, updatedTask);
      debugPrint('File saved to app directory: $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('Failed to save to app directory: $e');
      return null;
    }
  }

  /// 自动保存到 Download/MoonTV 目录
  Future<String?> autoSave(String taskId) async {
    final task = _downloadTasks[taskId];
    if (task == null) return null;
    final tempFile = File(task.tempFilePath);
    if (!tempFile.existsSync()) {
      return null;
    }
    try {
      // 获取 Download/MoonTV 目录
      final targetDir = await _getDownloadDirectory();
      // 构建目标路径，处理文件名冲突
      var targetPath = '${targetDir.path}/${task.fileName}';
      var counter = 1;
      final ext = path.extension(task.fileName);
      final baseName = path.basenameWithoutExtension(task.fileName);
      while (File(targetPath).existsSync()) {
        targetPath = '${targetDir.path}/${baseName}_$counter$ext';
        counter++;
      }
      // 移动临时文件到目标位置（使用 copy + delete 支持跨磁盘移动）
      await tempFile.copy(targetPath);
      await tempFile.delete();
      // 更新任务
      final updatedTask = task.copyWith(filePath: targetPath);
      _downloadTasks[taskId] = updatedTask;
      _notifyListeners(taskId, updatedTask);
      debugPrint('File auto-saved to: $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('Auto save failed: $e');
      return null;
    }
  }

  /// 获取下载目录 - 所有平台统一使用 Download/MoonTV
  Future<Directory> _getDownloadDirectory() async {
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

  /// 获取所有任务
  List<DownloadTask> getAllTasks() => _downloadTasks.values.toList();

  /// 获取指定任务
  DownloadTask? getTask(String taskId) => _downloadTasks[taskId];

  /// 通过URL获取任务
  DownloadTask? getTaskByUrl(String url) => _findTaskByUrl(url);

  /// 暂停下载
  Future<void> pauseDownload(String taskId) async {
    final task = _downloadTasks[taskId];
    if (task != null && task.status == DownloadStatus.downloading) {
      _cancelTokens[taskId]?.cancel();
      final pausedTask = task.copyWith(status: DownloadStatus.paused);
      _downloadTasks[taskId] = pausedTask;
      _notifyListeners(taskId, pausedTask);
    }
  }

  /// 恢复下载
  Future<void> resumeDownload(String taskId) async {
    final task = _downloadTasks[taskId];
    if (task != null && task.status == DownloadStatus.paused) {
      final resumedTask = task.copyWith(status: DownloadStatus.downloading);
      _downloadTasks[taskId] = resumedTask;
      _notifyListeners(taskId, resumedTask);
      await _performDownload(taskId);
    }
  }

  /// 取消下载并删除临时文件
  Future<void> cancelDownload(String taskId) async {
    // 取消下载
    _cancelTokens[taskId]?.cancel();
    final task = _downloadTasks[taskId];
    if (task != null) {
      // 删除临时文件
      await _cleanupTempFile(task.tempFilePath);
      // 从任务列表移除
      _downloadTasks.remove(taskId);
      _listeners.remove(taskId);
      _notifyListeners(taskId, task.copyWith(status: DownloadStatus.paused));
    }
  }

  /// 清理临时文件（带重试机制）
  Future<void> _cleanupTempFile(String tempPath) async {
    final file = File(tempPath);
    if (!file.existsSync()) {
      return;
    }

    // 重试机制：文件可能被占用，等待后重试
    const maxRetries = 5;
    const retryDelay = Duration(milliseconds: 200);

    for (var i = 0; i < maxRetries; i++) {
      try {
        await file.delete();
        debugPrint('Temp file deleted: $tempPath');
        return;
      } on PathAccessException catch (e) {
        if (i < maxRetries - 1) {
          debugPrint(
            'Temp file busy, retrying ${i + 1}/$maxRetries: $tempPath',
          );
          await Future<void>.delayed(retryDelay);
        } else {
          debugPrint('Failed to delete temp file after retries: $e');
        }
      } catch (e) {
        debugPrint('Failed to delete temp file: $e');
        return;
      }
    }
  }

  /// 清理所有临时文件
  Future<void> cleanupAllTempFiles() async {
    try {
      final tempDir = await _getTempDirectory();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
        await tempDir.create(recursive: true);
        debugPrint('All temp files cleaned up');
      }
    } catch (e) {
      debugPrint('Failed to cleanup temp files: $e');
    }
  }

  /// 清理已完成任务
  Future<void> clearCompletedTasks() async {
    final completedIds = _downloadTasks.entries
        .where((e) => e.value.status == DownloadStatus.completed)
        .map((e) => e.key)
        .toList();
    for (final id in completedIds) {
      _downloadTasks.remove(id);
      _listeners.remove(id);
    }
  }

  /// 获取下载进度
  double getProgress(String taskId) => _downloadTasks[taskId]?.progress ?? 0.0;

  /// 检查文件是否存在
  bool isFileExists(String path) => File(path).existsSync();

  /// 释放资源
  Future<void> dispose() async {
    // 取消所有进行中的下载
    for (final entry in _cancelTokens.entries) {
      final taskId = entry.key;
      final token = entry.value;
      token.cancel();
      // 清理临时文件
      final task = _downloadTasks[taskId];
      if (task != null) {
        await _cleanupTempFile(task.tempFilePath);
      }
    }
    _cancelTokens.clear();
    _listeners.clear();
    _taskLocks.clear();
  }
}
