/// 视频下载状态枚举
enum VideoDownloadState {
  idle,
  downloading,
  paused,
  completed,
  failed,
}

/// 视频下载信息类
///
/// 用于在播放器组件和控制器之间传递下载状态
class VideoDownloadInfo {
  final String? taskId;
  final VideoDownloadState state;
  final double progress;
  final String? filePath;
  final String? errorMessage;

  const VideoDownloadInfo({
    this.taskId,
    this.state = VideoDownloadState.idle,
    this.progress = 0.0,
    this.filePath,
    this.errorMessage,
  });

  VideoDownloadInfo copyWith({
    String? taskId,
    VideoDownloadState? state,
    double? progress,
    String? filePath,
    String? errorMessage,
  }) {
    return VideoDownloadInfo(
      taskId: taskId ?? this.taskId,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
