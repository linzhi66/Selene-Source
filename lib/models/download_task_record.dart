import 'package:hive/hive.dart';

class DownloadTaskRecord extends HiveObject {
  String taskId;
  String url;
  String fileName;
  String filePath;
  String tempFilePath;
  int totalBytes;
  int downloadedBytes;
  double progress;
  String status;
  String? errorMessage;
  DateTime createdAt;
  DateTime updatedAt;
  bool isM3u8;
  Map<String, String>? headers;
  String? videoTitle;
  String? coverUrl;
  String? episodeInfo;
  int? currentSegmentIndex;
  int? totalSegments;
  String? source;
  String? sourceId;

  DownloadTaskRecord({
    required this.taskId,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.tempFilePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.status = 'pending',
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isM3u8 = false,
    this.headers,
    this.videoTitle,
    this.coverUrl,
    this.episodeInfo,
    this.currentSegmentIndex,
    this.totalSegments,
    this.source,
    this.sourceId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  DownloadTaskRecord copyWith({
    String? taskId,
    String? url,
    String? fileName,
    String? filePath,
    String? tempFilePath,
    int? totalBytes,
    int? downloadedBytes,
    double? progress,
    String? status,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isM3u8,
    Map<String, String>? headers,
    String? videoTitle,
    String? coverUrl,
    String? episodeInfo,
    int? currentSegmentIndex,
    int? totalSegments,
    String? source,
    String? sourceId,
  }) {
    return DownloadTaskRecord(
      taskId: taskId ?? this.taskId,
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
      headers: headers ?? this.headers,
      videoTitle: videoTitle ?? this.videoTitle,
      coverUrl: coverUrl ?? this.coverUrl,
      episodeInfo: episodeInfo ?? this.episodeInfo,
      currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
      totalSegments: totalSegments ?? this.totalSegments,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
    );
  }

  bool get isDownloading => status == 'downloading';
  bool get isPaused => status == 'paused';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'pending';
  bool get canResume => isPaused || isFailed;
  bool get canPause => isDownloading;
  bool get canDelete => true;

  String get displayProgress {
    if (isCompleted) return '已完成';
    if (isFailed) return '下载失败';
    if (isPaused) return '已暂停 $_progressPercent%';
    if (isPending) return '等待中';
    return '$_progressPercent%';
  }

  int get _progressPercent => (progress * 100).round();

  String get displaySize {
    final mb = downloadedBytes / (1024 * 1024);
    final totalMb = totalBytes / (1024 * 1024);
    if (totalBytes > 0) {
      return '${mb.toStringAsFixed(1)}MB / ${totalMb.toStringAsFixed(1)}MB';
    }
    return '${mb.toStringAsFixed(1)}MB';
  }
}
