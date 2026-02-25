enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String id;
  final String url;
  final String title;
  final String episodeTitle;
  final String sourceName;
  final String cover;
  final String savePath;
  final int totalSegments;
  int downloadedSegments;
  final DateTime createdAt;
  DateTime? completedAt;
  DownloadStatus status;
  String? errorMessage;
  final int episodeIndex;
  final int totalEpisodes;

  DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.episodeTitle,
    required this.sourceName,
    required this.cover,
    required this.savePath,
    required this.totalSegments,
    this.downloadedSegments = 0,
    required this.createdAt,
    this.completedAt,
    this.status = DownloadStatus.pending,
    this.errorMessage,
    this.episodeIndex = 0,
    this.totalEpisodes = 1,
  });

  double get progress {
    if (totalSegments == 0) return 0.0;
    return downloadedSegments / totalSegments;
  }

  String get progressText {
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  String get statusText {
    switch (status) {
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
      case DownloadStatus.cancelled:
        return '已取消';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'episodeTitle': episodeTitle,
      'sourceName': sourceName,
      'cover': cover,
      'savePath': savePath,
      'totalSegments': totalSegments,
      'downloadedSegments': downloadedSegments,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'status': status.index,
      'errorMessage': errorMessage,
      'episodeIndex': episodeIndex,
      'totalEpisodes': totalEpisodes,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      title: json['title'] as String,
      episodeTitle: json['episodeTitle'] as String,
      sourceName: json['sourceName'] as String,
      cover: json['cover'] as String,
      savePath: json['savePath'] as String,
      totalSegments: json['totalSegments'] as int,
      downloadedSegments: json['downloadedSegments'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      status: DownloadStatus.values[json['status'] as int? ?? 0],
      errorMessage: json['errorMessage'] as String?,
      episodeIndex: json['episodeIndex'] as int? ?? 0,
      totalEpisodes: json['totalEpisodes'] as int? ?? 1,
    );
  }

  DownloadTask copyWith({
    String? id,
    String? url,
    String? title,
    String? episodeTitle,
    String? sourceName,
    String? cover,
    String? savePath,
    int? totalSegments,
    int? downloadedSegments,
    DateTime? createdAt,
    DateTime? completedAt,
    DownloadStatus? status,
    String? errorMessage,
    int? episodeIndex,
    int? totalEpisodes,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      sourceName: sourceName ?? this.sourceName,
      cover: cover ?? this.cover,
      savePath: savePath ?? this.savePath,
      totalSegments: totalSegments ?? this.totalSegments,
      downloadedSegments: downloadedSegments ?? this.downloadedSegments,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
    );
  }
}
