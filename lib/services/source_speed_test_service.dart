import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 测速结果数据类
class SpeedTestResult {
  final String sourceId;
  final String quality;
  final String loadSpeed;
  final String pingTime;
  final double downloadSpeedKBps;
  final int latencyMs;
  final bool success;
  final String error;
  final DateTime testTime;

  const SpeedTestResult({
    required this.sourceId,
    this.quality = '未知',
    this.loadSpeed = '超时',
    this.pingTime = '超时',
    this.downloadSpeedKBps = 0.0,
    this.latencyMs = 0,
    this.success = false,
    this.error = '',
    required this.testTime,
  });

  /// 转换为面板所需的 Map 格式
  Map<String, String> toMap() => {
        'quality': quality,
        'loadSpeed': loadSpeed,
        'pingTime': pingTime,
      };

  /// 创建失败的测速结果
  factory SpeedTestResult.failed(String sourceId, {String error = ''}) =>
      SpeedTestResult(
        sourceId: sourceId,
        success: false,
        error: error,
        testTime: DateTime.now(),
      );
}

/// 测速配置
class SpeedTestConfig {
  /// 最大并发数
  final int maxConcurrency;

  /// 连接超时时间
  final Duration connectTimeout;

  /// 接收超时时间
  final Duration receiveTimeout;

  /// 单次测速总超时时间
  final Duration totalTimeout;

  /// 是否启用快速模式（只测延迟，不下载片段）
  final bool fastMode;

  /// 快速模式下测速超时时间
  final Duration fastModeTimeout;

  /// 完整模式下下载的片段数量
  final int segmentsToDownload;

  /// 是否启用智能预筛选（先快速测延迟，再深度测速）
  final bool smartPreFilter;

  /// 智能预筛选的延迟阈值（低于此值的源才进行深度测速）
  final int latencyThresholdMs;

  const SpeedTestConfig({
    this.maxConcurrency = 5,
    this.connectTimeout = const Duration(seconds: 3),
    this.receiveTimeout = const Duration(seconds: 5),
    this.totalTimeout = const Duration(seconds: 8),
    this.fastMode = false,
    this.fastModeTimeout = const Duration(seconds: 2),
    this.segmentsToDownload = 1,
    this.smartPreFilter = true,
    this.latencyThresholdMs = 500,
  });

  /// 快速模式配置
  static const SpeedTestConfig fast = SpeedTestConfig(
    maxConcurrency: 8,
    connectTimeout: Duration(seconds: 2),
    receiveTimeout: Duration(seconds: 3),
    totalTimeout: Duration(seconds: 5),
    fastMode: true,
    fastModeTimeout: Duration(seconds: 2),
    smartPreFilter: false,
  );

  /// 标准模式配置
  static const SpeedTestConfig standard = SpeedTestConfig(
    maxConcurrency: 5,
    connectTimeout: Duration(seconds: 3),
    receiveTimeout: Duration(seconds: 5),
    totalTimeout: Duration(seconds: 8),
    fastMode: false,
    segmentsToDownload: 1,
    smartPreFilter: true,
  );

  /// 深度模式配置（更严格，更准确）
  static const SpeedTestConfig deep = SpeedTestConfig(
    maxConcurrency: 3,
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 10),
    totalTimeout: Duration(seconds: 15),
    fastMode: false,
    segmentsToDownload: 2,
    smartPreFilter: true,
    latencyThresholdMs: 300,
  );
}

/// 视频源测速服务 - 优化版本
///
/// 主要优化点：
/// 1. 限制并发数，避免网络拥塞
/// 2. 支持取消操作
/// 3. 提供快速/标准/深度三种测速模式
/// 4. 智能预筛选，优先测延迟快的源
/// 5. 渐进式返回结果
class SourceSpeedTestService {
  late final Dio _dio;
  final _cancelTokens = HashSet<CancelToken>();
  bool _isDisposed = false;

  SourceSpeedTestService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept': '*/*',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ),
    );
  }

  /// 批量测速所有源
  ///
  /// [sources] - 视频源列表，每个源需要包含 source, id, episodes 字段
  /// [onResult] - 每个源测速完成后的回调（实时更新）
  /// [config] - 测速配置
  /// [onProgress] - 测速进度回调 (已完成数量, 总数)
  Future<Map<String, SpeedTestResult>> testAllSources({
    required List<dynamic> sources,
    required void Function(SpeedTestResult result) onResult,
    SpeedTestConfig config = SpeedTestConfig.standard,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_isDisposed) {
      throw StateError('Service has been disposed');
    }

    if (sources.isEmpty) {
      return {};
    }

    final results = <String, SpeedTestResult>{};
    final pendingSources = Queue<dynamic>.from(sources);
    var completedCount = 0;
    final totalCount = sources.length;

    // 创建进度定时器，避免过于频繁的回调
    Timer? progressTimer;
    var lastReportedProgress = 0;

    void reportProgress() {
      if (onProgress != null && completedCount > lastReportedProgress) {
        lastReportedProgress = completedCount;
        onProgress(completedCount, totalCount);
      }
    }

    if (onProgress != null) {
      progressTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => reportProgress(),
      );
    }

    // 使用信号量控制并发数
    final semaphore = _Semaphore(config.maxConcurrency);
    final futures = <Future<void>>[];

    // 处理每个源
    while (pendingSources.isNotEmpty) {
      final source = pendingSources.removeFirst();
      final sourceId = '${source.source}_${source.id}';

      // 选择要测试的集数链接
      final episodeUrl = _selectTestEpisode(source);
      if (episodeUrl == null || episodeUrl.isEmpty) {
        // 跳过没有有效链接的源
        final result = SpeedTestResult.failed(
          sourceId,
          error: '没有有效的视频链接',
        );
        results[sourceId] = result;
        onResult(result);
        completedCount++;
        continue;
      }

      // 获取信号量，控制并发
      final permit = await semaphore.acquire();

      final future = _testSingleSourceWithSemaphore(
        sourceId: sourceId,
        episodeUrl: episodeUrl,
        config: config,
        semaphorePermit: permit,
        onResult: (result) {
          results[sourceId] = result;
          onResult(result);
          completedCount++;
        },
      );

      futures.add(future);
    }

    // 等待所有测速完成
    await Future.wait(futures);

    // 停止进度定时器并发送最终进度
    progressTimer?.cancel();
    reportProgress();

    return results;
  }

  /// 带信号量的单源测速
  Future<void> _testSingleSourceWithSemaphore({
    required String sourceId,
    required String episodeUrl,
    required SpeedTestConfig config,
    required _SemaphorePermit semaphorePermit,
    required void Function(SpeedTestResult result) onResult,
  }) async {
    try {
      final result = await _testSingleSource(
        sourceId: sourceId,
        episodeUrl: episodeUrl,
        config: config,
      );
      onResult(result);
    } finally {
      semaphorePermit.release();
    }
  }

  /// 测试单个源
  Future<SpeedTestResult> _testSingleSource({
    required String sourceId,
    required String episodeUrl,
    required SpeedTestConfig config,
  }) async {
    // 创建取消令牌
    final cancelToken = CancelToken();
    _cancelTokens.add(cancelToken);

    try {
      // 更新 Dio 配置
      _dio.options.connectTimeout = config.connectTimeout;
      _dio.options.receiveTimeout = config.receiveTimeout;

      // 快速模式：只测延迟
      if (config.fastMode) {
        return await _testFastMode(
          sourceId: sourceId,
          episodeUrl: episodeUrl,
          config: config,
          cancelToken: cancelToken,
        );
      }

      // 智能预筛选模式
      if (config.smartPreFilter) {
        return await _testSmartMode(
          sourceId: sourceId,
          episodeUrl: episodeUrl,
          config: config,
          cancelToken: cancelToken,
        );
      }

      // 标准模式：完整测速
      return await _testFullMode(
        sourceId: sourceId,
        episodeUrl: episodeUrl,
        config: config,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return SpeedTestResult.failed(sourceId, error: '测速已取消');
      }
      return SpeedTestResult.failed(sourceId, error: e.message ?? '网络错误');
    } catch (e) {
      return SpeedTestResult.failed(sourceId, error: e.toString());
    } finally {
      _cancelTokens.remove(cancelToken);
    }
  }

  /// 快速模式测速（只测延迟）
  Future<SpeedTestResult> _testFastMode({
    required String sourceId,
    required String episodeUrl,
    required SpeedTestConfig config,
    required CancelToken cancelToken,
  }) async {
    // 只获取 M3U8 并测量延迟
    final stopwatch = Stopwatch()..start();

    final response = await _dio.get<String>(
      episodeUrl,
      cancelToken: cancelToken,
    );

    stopwatch.stop();
    final latencyMs = stopwatch.elapsedMilliseconds;

    // 解析分辨率
    final resolution = _parseResolution(response.data ?? '');

    return SpeedTestResult(
      sourceId: sourceId,
      quality: resolution,
      loadSpeed: latencyMs < 200 ? '极快' : (latencyMs < 500 ? '较快' : '一般'),
      pingTime: '${latencyMs}ms',
      downloadSpeedKBps: 0.0,
      latencyMs: latencyMs,
      success: true,
      testTime: DateTime.now(),
    );
  }

  /// 智能模式测速（先快速筛选，再深度测速）
  Future<SpeedTestResult> _testSmartMode({
    required String sourceId,
    required String episodeUrl,
    required SpeedTestConfig config,
    required CancelToken cancelToken,
  }) async {
    // 第一阶段：快速获取 M3U8 并测量延迟
    final quickResult = await _quickTest(
      episodeUrl: episodeUrl,
      config: config,
      cancelToken: cancelToken,
    );

    if (!quickResult.success) {
      return SpeedTestResult.failed(sourceId, error: quickResult.error);
    }

    // 如果延迟过高，跳过深度测速
    if (quickResult.latencyMs > config.latencyThresholdMs) {
      return SpeedTestResult(
        sourceId: sourceId,
        quality: quickResult.quality,
        loadSpeed: '延迟高',
        pingTime: '${quickResult.latencyMs}ms',
        downloadSpeedKBps: 0.0,
        latencyMs: quickResult.latencyMs,
        success: true,
        testTime: DateTime.now(),
      );
    }

    // 第二阶段：深度测速（下载片段）
    if (quickResult.segments.isNotEmpty) {
      final downloadResult = await _testDownloadSpeed(
        segments: quickResult.segments,
        config: config,
        cancelToken: cancelToken,
      );

      return SpeedTestResult(
        sourceId: sourceId,
        quality: quickResult.quality,
        loadSpeed: _formatDownloadSpeed(downloadResult.speedKBps),
        pingTime: '${quickResult.latencyMs}ms',
        downloadSpeedKBps: downloadResult.speedKBps,
        latencyMs: quickResult.latencyMs,
        success: true,
        testTime: DateTime.now(),
      );
    }

    // 没有片段，只返回延迟信息
    return SpeedTestResult(
      sourceId: sourceId,
      quality: quickResult.quality,
      loadSpeed: '未知',
      pingTime: '${quickResult.latencyMs}ms',
      downloadSpeedKBps: 0.0,
      latencyMs: quickResult.latencyMs,
      success: true,
      testTime: DateTime.now(),
    );
  }

  /// 完整模式测速
  Future<SpeedTestResult> _testFullMode({
    required String sourceId,
    required String episodeUrl,
    required SpeedTestConfig config,
    required CancelToken cancelToken,
  }) async {
    // 获取 M3U8 内容
    final stopwatch = Stopwatch()..start();

    final response = await _dio.get<String>(
      episodeUrl,
      cancelToken: cancelToken,
    );

    stopwatch.stop();
    final latencyMs = stopwatch.elapsedMilliseconds;

    // 解析分辨率和片段
    final content = response.data ?? '';
    final resolution = _parseResolution(content);
    final segments = _parseSegments(content, episodeUrl);

    // 测量下载速度
    double speedKBps = 0.0;
    if (segments.isNotEmpty) {
      final downloadResult = await _testDownloadSpeed(
        segments: segments,
        config: config,
        cancelToken: cancelToken,
      );
      speedKBps = downloadResult.speedKBps;
    }

    return SpeedTestResult(
      sourceId: sourceId,
      quality: resolution,
      loadSpeed: _formatDownloadSpeed(speedKBps),
      pingTime: '${latencyMs}ms',
      downloadSpeedKBps: speedKBps,
      latencyMs: latencyMs,
      success: true,
      testTime: DateTime.now(),
    );
  }

  /// 快速测试（返回延迟和基本信息）
  Future<_QuickTestResult> _quickTest({
    required String episodeUrl,
    required SpeedTestConfig config,
    required CancelToken cancelToken,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();

      final response = await _dio.get<String>(
        episodeUrl,
        cancelToken: cancelToken,
      );

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;

      final content = response.data ?? '';
      final resolution = _parseResolution(content);
      final segments = _parseSegments(content, episodeUrl);

      return _QuickTestResult(
        success: true,
        latencyMs: latencyMs,
        quality: resolution,
        segments: segments,
      );
    } catch (e) {
      return _QuickTestResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// 测试下载速度
  Future<_DownloadTestResult> _testDownloadSpeed({
    required List<String> segments,
    required SpeedTestConfig config,
    required CancelToken cancelToken,
  }) async {
    final segmentsToTest = segments.take(config.segmentsToDownload).toList();

    if (segmentsToTest.isEmpty) {
      return _DownloadTestResult(speedKBps: 0.0);
    }

    final stopwatch = Stopwatch()..start();
    var totalBytes = 0;
    var successfulDownloads = 0;

    // 串行下载片段，避免同时占用过多带宽
    for (final segmentUrl in segmentsToTest) {
      if (cancelToken.isCancelled) break;

      try {
        final response = await _dio.get<Uint8List>(
          segmentUrl,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: config.receiveTimeout,
          ),
          cancelToken: cancelToken,
        );

        final bytes = response.data?.length ?? 0;
        totalBytes += bytes;
        successfulDownloads++;
      } catch (e) {
        // 忽略单个片段下载失败
      }
    }

    stopwatch.stop();

    if (successfulDownloads == 0 || totalBytes == 0) {
      return _DownloadTestResult(speedKBps: 0.0);
    }

    final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
    final speedKBps = (totalBytes / 1024) / elapsedSeconds;

    return _DownloadTestResult(speedKBps: speedKBps);
  }

  /// 从 M3U8 内容解析分辨率
  String _parseResolution(String content) {
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#EXT-X-STREAM-INF:')) {
        final resolutionMatch =
            RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(trimmed);
        if (resolutionMatch != null) {
          final width = int.tryParse(resolutionMatch.group(1) ?? '0') ?? 0;
          return _convertResolutionToString(width);
        }
      }
    }

    return '未知';
  }

  /// 从 M3U8 内容解析片段 URL
  List<String> _parseSegments(String content, String baseUrl) {
    final lines = content.split('\n');
    final segments = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      segments.add(_resolveUrl(trimmed, baseUrl));
    }

    return segments;
  }

  /// 解析相对 URL 为绝对 URL
  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    final baseUri = Uri.parse(baseUrl);
    if (url.startsWith('/')) {
      return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}$url';
    } else {
      final basePath =
          baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
      return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}$basePath$url';
    }
  }

  /// 将宽度转换为分辨率字符串
  String _convertResolutionToString(int width) {
    if (width >= 3840) return '4K';
    if (width >= 2560) return '2K';
    if (width >= 1920) return '1080p';
    if (width >= 1280) return '720p';
    if (width >= 854) return '480p';
    if (width >= 640) return '360p';
    return 'SD';
  }

  /// 格式化下载速度
  String _formatDownloadSpeed(double speedKBps) {
    if (speedKBps <= 0) return '超时';
    if (speedKBps >= 1024) {
      return '${(speedKBps / 1024).toStringAsFixed(1)}MB/s';
    }
    return '${speedKBps.toStringAsFixed(1)}KB/s';
  }

  /// 选择要测试的集数链接
  String? _selectTestEpisode(dynamic source) {
    final episodes = source.episodes;
    if (episodes == null || episodes.isEmpty) {
      return null;
    }

    // 优先选择第二集，避免第一集可能是预告片或片头
    if (episodes.length >= 2) {
      return episodes[1] as String?;
    }
    return episodes[0] as String?;
  }

  /// 取消所有正在进行的测速
  void cancelAllTests() {
    for (final token in _cancelTokens.toList()) {
      if (!token.isCancelled) {
        token.cancel('测速被取消');
      }
    }
    _cancelTokens.clear();
  }

  /// 释放资源
  void dispose() {
    _isDisposed = true;
    cancelAllTests();
    _dio.close();
  }
}

/// 快速测试结果内部类
class _QuickTestResult {
  final bool success;
  final int latencyMs;
  final String quality;
  final List<String> segments;
  final String error;

  _QuickTestResult({
    required this.success,
    this.latencyMs = 0,
    this.quality = '未知',
    this.segments = const [],
    this.error = '',
  });
}

/// 下载测试结果内部类
class _DownloadTestResult {
  final double speedKBps;

  _DownloadTestResult({required this.speedKBps});
}

/// 信号量实现 - 用于控制并发数
class _Semaphore {
  final int maxPermits;
  int _currentPermits;
  final _waitQueue = Queue<Completer<_SemaphorePermit>>();

  _Semaphore(this.maxPermits) : _currentPermits = maxPermits;

  Future<_SemaphorePermit> acquire() async {
    if (_currentPermits > 0) {
      _currentPermits--;
      return _SemaphorePermit(this);
    }

    final completer = Completer<_SemaphorePermit>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete(_SemaphorePermit(this));
    } else {
      _currentPermits++;
    }
  }
}

/// 信号量许可
class _SemaphorePermit {
  final _Semaphore _semaphore;
  bool _released = false;

  _SemaphorePermit(this._semaphore);

  void release() {
    if (!_released) {
      _released = true;
      _semaphore.release();
    }
  }
}
