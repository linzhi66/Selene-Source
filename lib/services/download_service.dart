import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:encrypt/encrypt.dart' hide Key, IV;
import 'package:flutter/foundation.dart';
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
  final String url;
  final String fileName;
  final String filePath;
  int totalBytes;
  int downloadedBytes;
  double progress;
  DownloadStatus status;
  String? errorMessage;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 构造函数
  DownloadTask({
    required this.url,
    required this.fileName,
    required this.filePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.status = DownloadStatus.waiting,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 从JSON创建DownloadTask实例
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
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
    );
  }

  /// 转换DownloadTask实例为JSON
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'fileName': fileName,
      'filePath': filePath,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
      'progress': progress,
      'status': status.name,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 复制并更新DownloadTask实例
  DownloadTask copyWith({
    String? url,
    String? fileName,
    String? filePath,
    int? totalBytes,
    int? downloadedBytes,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    /// 返回一个新的 DownloadTask 实例，属性根据传入参数更新
    return DownloadTask(
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// HLS片段信息（含加密/字节范围）
class _HlsSegment {
  final String url;
  final int durationMs;
  final int? byteRangeLength;
  final int? byteRangeOffset;

  // AES-128密钥URL
  final String? keyUri;

  // 16字节IV（若无则用序列号生成）
  final Uint8List? iv;

  // 媒体序列号（用于生成IV）
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

  late Dio _dio;

  /// 下载任务映射
  final Map<String, DownloadTask> _downloadTasks = {};

  /// 任务监听器映射
  final Map<String, List<ValueChanged<DownloadTask>>> _listeners = {};

  /// 取消令牌映射
  final Map<String, CancelToken> _cancelTokens = {};

  /// 初始化
  Future<void> initialize() async {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ));
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        request: false,
        responseBody: false,
        error: true,
        requestBody: false,
      ));
    }
  }

  /// 添加监听器
  void addListener(String taskId, ValueChanged<DownloadTask> listener) {
    _listeners.putIfAbsent(taskId, () => []).add(listener);
  }

  /// 移除监听器
  void removeListener(String taskId, ValueChanged<DownloadTask> listener) {
    final list = _listeners[taskId];
    if (list != null) {
      list.remove(listener);
      if (list.isEmpty) _listeners.remove(taskId);
    }
  }

  /// 通知监听器任务更新
  void _notifyListeners(String taskId, DownloadTask task) {
    final list = _listeners[taskId];
    if (list != null) {
      for (final l in List.of(list)) {
        try {
          l(task);
        } catch (e) {
          debugPrint('Listener error: $e');
        }
      }
    }
  }

  /// 启动下载
  Future<DownloadTask> startDownload({
    required String url,
    required String fileName,
    String? customPath,
    Map<String, String>? headers,
    String? episodeInfo,
  }) async {
    final taskId = url.hashCode.toString();
    if (_downloadTasks.containsKey(taskId)) {
      final existing = _downloadTasks[taskId]!;
      if (existing.status == DownloadStatus.downloading) return existing;
    }
    try {
      final dir = await _getDownloadDirectory();
      String finalName = fileName;
      if (episodeInfo != null && episodeInfo.isNotEmpty) {
        final ext = fileName.contains('.')
            ? fileName.substring(fileName.lastIndexOf('.'))
            : '.mp4';
        final base = fileName.substring(
            0,
            fileName.lastIndexOf('.') > 0
                ? fileName.lastIndexOf('.')
                : fileName.length);
        finalName = '${base.trim()}-$episodeInfo$ext';
      }
      final path = customPath ?? '${dir.path}/$finalName';
      final task = DownloadTask(url: url, fileName: finalName, filePath: path);
      _downloadTasks[taskId] = task;
      final downloadingTask = task.copyWith(status: DownloadStatus.downloading);
      _downloadTasks[taskId] = downloadingTask;
      _notifyListeners(taskId, downloadingTask);
      await _performDownload(taskId, headers: headers);
      return _downloadTasks[taskId]!;
    } catch (e, st) {
      debugPrint('Start download failed: $e\n$st');
      final failed = _downloadTasks[taskId]?.copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
          ) ??
          DownloadTask(
            url: url,
            fileName: fileName,
            filePath: customPath ??
                '${(await _getDownloadDirectory()).path}/$fileName',
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
          );
      _downloadTasks[taskId] = failed;
      _notifyListeners(taskId, failed);
      return failed;
    }
  }

  /// 执行下载任务（支持M3U8和普通文件）
  Future<void> _performDownload(String taskId,
      {Map<String, String>? headers}) async {
    final task = _downloadTasks[taskId];
    if (task == null || task.status != DownloadStatus.downloading) return;
    try {
      if (task.url.toLowerCase().endsWith('.m3u8')) {
        await _downloadAndMergeM3u8(taskId, headers: headers);
      } else {
        // 普通文件下载（保留原逻辑）
        final Response<dynamic> headRes =
            await _dio.head(task.url, options: Options(headers: headers));
        final total =
            int.tryParse(headRes.headers.value('content-length') ?? '0') ?? 0;
        _downloadTasks[taskId] = task.copyWith(totalBytes: total);
        final updatedTask = _downloadTasks[taskId];
        if (updatedTask != null) {
          _notifyListeners(taskId, updatedTask);
        }
        final cancelToken = CancelToken();
        _cancelTokens[taskId] = cancelToken;
        await _dio.download(
          task.url,
          task.filePath,
          options: Options(
              headers: headers, receiveTimeout: const Duration(minutes: 30)),
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total <= 0) return;
            final task = _downloadTasks[taskId];
            if (task != null) {
              final updated = task.copyWith(
                downloadedBytes: received,
                progress: received / total,
              );
              _downloadTasks[taskId] = updated;
              _notifyListeners(taskId, updated);
            }
          },
        );
      }
      // 下载完成处理
      final currentDownloadTask = _downloadTasks[taskId];
      if (currentDownloadTask != null &&
          currentDownloadTask.status == DownloadStatus.downloading) {
        final completed = currentDownloadTask.copyWith(
          status: DownloadStatus.completed,
          downloadedBytes: await _getFileSize(task.filePath),
          progress: 1.0,
        );
        _downloadTasks[taskId] = completed;
        _notifyListeners(taskId, completed);
        debugPrint('✅ Download completed: ${task.fileName}');
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        debugPrint('Download canceled: ${task.fileName}');
        return;
      }
      debugPrint('Download error: $e');
      final currentDownloadTask = _downloadTasks[taskId];
      if (currentDownloadTask != null) {
        final failed = currentDownloadTask.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        );
        _downloadTasks[taskId] = failed;
        _notifyListeners(taskId, failed);
      }
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// 下载并合并M3U8视频流
  Future<void> _downloadAndMergeM3u8(String taskId,
      {Map<String, String>? headers}) async {
    final task = _downloadTasks[taskId];
    if (task == null) return;
    debugPrint('🎬 Starting M3U8 download: ${task.url}');
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;
    try {
      // 1. 获取并解析M3U8（自动处理主列表→子列表）
      final (segments, baseUrl) =
          await _resolveM3u8Playlist(task.url, headers, cancelToken);
      if (segments.isEmpty) throw Exception('No TS segments found');
      debugPrint('📦 Found ${segments.length} TS segments (base: $baseUrl)');
      _updateProgress(taskId, 0, 0);
      // 2. 创建输出文件（清空旧文件）
      final outputFile = File(task.filePath);
      if (outputFile.existsSync()) await outputFile.delete();
      final sink = outputFile.openWrite(mode: FileMode.write);
      // 3. 密钥缓存 & 下载状态
      final keyCache = <String, Uint8List>{};
      int downloadedCount = 0;
      int totalBytes = 0;
      // 4. 流式处理每个片段
      for (int i = 0; i < segments.length; i++) {
        if (cancelToken.isCancelled ||
            (_downloadTasks[taskId]?.status != DownloadStatus.downloading)) {
          await sink.close();
          throw DioException(
              type: DioExceptionType.cancel,
              requestOptions: RequestOptions(path: ''));
        }
        final seg = segments[i];
        Uint8List? segmentData;
        // 4.1 下载密钥（如需）
        Uint8List? keyBytes;
        if (seg.keyUri != null) {
          if (!keyCache.containsKey(seg.keyUri!)) {
            final keyUrl = _resolveUrl(baseUrl, seg.keyUri!);
            final Response<List<int>> keyRes = await _dio.get<List<int>>(
              keyUrl,
              options:
                  Options(responseType: ResponseType.bytes, headers: headers),
              cancelToken: cancelToken,
            );
            keyCache[seg.keyUri!] =
                Uint8List.fromList(keyRes.data as List<int>);
            debugPrint('🔑 Cached key from $keyUrl');
          }
          keyBytes = keyCache[seg.keyUri!];
        }
        // 4.2 构建TS请求（处理字节范围）
        final tsUrl = _resolveUrl(baseUrl, seg.url);
        final Options opts =
            Options(headers: Map<String, String>.from(headers ?? {}));
        if (seg.byteRangeLength != null) {
          final start = seg.byteRangeOffset ?? 0;
          final end = start + seg.byteRangeLength! - 1;
          opts.headers?['Range'] = 'bytes=$start-$end';
          debugPrint('byterange: $start-$end for ${seg.url}');
        }
        // 4.3 下载TS片段
        final tsRes = await _dio.get<List<int>>(
          tsUrl,
          options: opts..responseType = ResponseType.bytes,
          cancelToken: cancelToken,
        );
        segmentData = Uint8List.fromList(tsRes.data as List<int>);
        totalBytes += segmentData.length;
        // 4.4 按需解密（AES-128 CBC 无填充）
        if (keyBytes != null) {
          final iv = seg.iv ?? _generateIvFromSequence(seg.sequenceNumber);
          segmentData = _decryptAes128Cbc(segmentData, keyBytes, iv);
          debugPrint(
              '🔓 Decrypted segment ${i + 1}/${segments.length} (seq: ${seg.sequenceNumber})');
        }
        // 4.5 流式写入（关键：避免临时文件）
        sink.add(segmentData);
        downloadedCount++;
        // 4.6 更新进度（按片段数+字节数双维度）
        final progress = downloadedCount / segments.length;
        _updateProgress(taskId, progress, totalBytes);
      }
      await sink.close();
      debugPrint('✅ M3U8 merged successfully to ${task.filePath}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('M3U8 download canceled');
        rethrow;
      }
      debugPrint('M3U8 download error: ${e.message}');
      rethrow;
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// 递归解析M3U8（主列表→最高码率子列表→媒体列表）
  Future<(List<_HlsSegment>, String)> _resolveM3u8Playlist(
    String url,
    Map<String, String>? headers,
    CancelToken cancelToken,
  ) async {
    final Response<String> res = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain, headers: headers),
      cancelToken: cancelToken,
    );
    final content = res.data as String;
    final baseUrl = _getBaseUrl(url);
    // 检查是否为主列表（含#EXT-X-STREAM-INF）
    if (content.contains('#EXT-X-STREAM-INF:')) {
      debugPrint('🔍 Detected master playlist, selecting highest bitrate...');
      final subUrl = _selectHighestBitrateStream(content, baseUrl);
      if (subUrl.isEmpty) {
        throw Exception('No valid stream found in master playlist');
      }
      return _resolveM3u8Playlist(subUrl, headers, cancelToken); // 递归解析子列表
    }
    // 解析媒体列表
    return (_parseMediaPlaylist(content, baseUrl), baseUrl);
  }

  /// 从主列表选择最高码率流
  String _selectHighestBitrateStream(String content, String baseUrl) {
    String bestUrl = '';
    int maxBandwidth = 0;
    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        if (bwMatch != null) {
          final bw = int.parse(bwMatch.group(1)!);
          // 找下一行非注释行
          int j = i + 1;
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
    int currentDuration = 0;
    int? currentByteRangeLength, currentByteRangeOffset;
    // 起始序列号
    int mediaSequence = 0;
    // 当前片段在列表中的索引
    int segmentIndex = 0;
    // 提取起始序列号（如有）
    final seqMatch = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(content);
    if (seqMatch != null) mediaSequence = int.parse(seqMatch.group(1)!);
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
              currentIv = Uint8List.fromList(
                hex
                    .split(RegExp('.{1,2}'))
                    .where((s) => s.isNotEmpty)
                    .map((b) => int.parse(b, radix: 16))
                    .toList(),
              );
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
        segments.add(_HlsSegment(
          url: absUrl,
          durationMs: currentDuration,
          byteRangeLength: currentByteRangeLength,
          byteRangeOffset: currentByteRangeOffset,
          keyUri: currentKeyUri,
          iv: currentIv,
          sequenceNumber: mediaSequence + segmentIndex, // 关键：序列号=起始+索引
        ));
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
    return '${uri.scheme}://${uri.host}${uri.path.substring(0, uri.path.lastIndexOf('/') + 1)}';
  }

  /// 解析相对URL为绝对URL
  String _resolveUrl(String baseUrl, String relative) {
    if (relative.startsWith('http')) return relative;
    if (relative.startsWith('//')) {
      return '${Uri.parse(baseUrl).scheme}:$relative';
    }
    if (relative.startsWith('/')) {
      final baseUri = Uri.parse(baseUrl);
      return '${baseUri.scheme}://${baseUri.host}$relative';
    }
    return baseUrl + relative;
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
      Uint8List encrypted, Uint8List key, Uint8List iv) {
    if (key.length != 16 || iv.length != 16) {
      throw ArgumentError('Key and IV must be 16 bytes for AES-128');
    }
    try {
      final ivParam = enc.IV(iv);
      final keyParam = enc.Key(key);
      final encrypter = Encrypter(
          AES(keyParam, mode: AESMode.cbc, padding: null)); // null = NoPadding
      final encryptedData = Encrypted(encrypted);
      final decrypted = encrypter.decrypt(encryptedData, iv: ivParam);
      // 将解密后的字符串转换回 Uint8List
      return Uint8List.fromList(utf8.encode(decrypted));
    } catch (e) {
      debugPrint(
          '⚠️ Decryption failed (length: ${encrypted.length}, key: ${key.length}, iv: ${iv.length}): $e');
      rethrow;
    }
  }

  /// 更新下载进度
  void _updateProgress(String taskId, double progress, int bytes) {
    final task = _downloadTasks[taskId];
    if (task != null && task.status == DownloadStatus.downloading) {
      final updated = task.copyWith(
        progress: progress.clamp(0.0, 1.0),
        downloadedBytes: bytes,
      );
      _downloadTasks[taskId] = updated;
      _notifyListeners(taskId, updated);
    }
  }

  /// 获取下载目录
  Future<Directory> _getDownloadDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      // Android 10+ 需使用应用专属目录（避免Scoped Storage问题）
      dir = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${dir.path}/videos');
      if (!videoDir.existsSync()) await videoDir.create(recursive: true);
      return videoDir;
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
      return dir;
    } else {
      dir = (await getDownloadsDirectory()) ??
          await getApplicationDocumentsDirectory();
      final videoDir = Directory('${dir.path}/MoonTV');
      if (!videoDir.existsSync()) await videoDir.create(recursive: true);
      return videoDir;
    }
  }

  /// 获取文件大小
  Future<int> _getFileSize(String path) async {
    try {
      final file = File(path);
      return (file.existsSync()) ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 获取所有任务
  List<DownloadTask> getAllTasks() => _downloadTasks.values.toList();

  /// 获取指定任务
  DownloadTask? getTask(String taskId) => _downloadTasks[taskId];

  /// 暂停下载
  Future<void> pauseDownload(String taskId) async {
    final currentTask = _downloadTasks[taskId];
    if (currentTask != null &&
        currentTask.status == DownloadStatus.downloading) {
      _cancelTokens[taskId]?.cancel();
      final paused = currentTask.copyWith(status: DownloadStatus.paused);
      _downloadTasks[taskId] = paused;
      _notifyListeners(taskId, paused);
    }
  }

  /// 恢复下载
  Future<void> resumeDownload(String taskId) async {
    final currentTask = _downloadTasks[taskId];
    if (currentTask != null && currentTask.status == DownloadStatus.paused) {
      final resumed = currentTask.copyWith(status: DownloadStatus.downloading);
      _downloadTasks[taskId] = resumed;
      _notifyListeners(taskId, resumed);
      await _performDownload(taskId);
    }
  }

  /// 取消下载并删除文件
  Future<void> cancelDownload(String taskId) async {
    _cancelTokens[taskId]?.cancel();
    final task = _downloadTasks[taskId];
    if (task != null) {
      final file = File(task.filePath);
      if (file.existsSync()) {
        await file.delete();
      }
      _downloadTasks.remove(taskId);
      _notifyListeners(taskId, task.copyWith(status: DownloadStatus.paused));
    }
  }

  /// 清理已完成任务
  Future<void> clearCompletedTasks() async {
    final ids = _downloadTasks.entries
        .where((e) => e.value.status == DownloadStatus.completed)
        .map((e) => e.key)
        .toList();
    for (final id in ids) {
      _downloadTasks.remove(id);
    }
  }

  /// 获取下载进度
  double getProgress(String taskId) => _downloadTasks[taskId]?.progress ?? 0.0;

  /// 检查文件是否存在
  bool isFileExists(String path) => File(path).existsSync();
}
