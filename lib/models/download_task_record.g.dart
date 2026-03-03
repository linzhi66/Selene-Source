import 'package:hive/hive.dart';
import 'package:selene/models/download_task_record.dart';

class DownloadTaskRecordAdapter extends TypeAdapter<DownloadTaskRecord> {
  @override
  final int typeId = 5;

  @override
  void write(BinaryWriter writer, DownloadTaskRecord obj) {
    writer.writeString(obj.taskId);
    writer.writeString(obj.url);
    writer.writeString(obj.fileName);
    writer.writeString(obj.filePath);
    writer.writeString(obj.tempFilePath);
    writer.writeInt(obj.totalBytes);
    writer.writeInt(obj.downloadedBytes);
    writer.writeDouble(obj.progress);
    writer.writeString(obj.status);
    writer.writeString(obj.errorMessage ?? '');
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
    writer.writeBool(obj.isM3u8);
    writer.writeMap(obj.headers ?? {});
    writer.writeString(obj.videoTitle ?? '');
    writer.writeString(obj.coverUrl ?? '');
    writer.writeString(obj.episodeInfo ?? '');
    writer.writeInt(obj.currentSegmentIndex ?? -1);
    writer.writeInt(obj.totalSegments ?? -1);
    writer.writeString(obj.source ?? '');
    writer.writeString(obj.sourceId ?? '');
  }

  @override
  DownloadTaskRecord read(BinaryReader reader) {
    final taskId = reader.readString();
    final url = reader.readString();
    final fileName = reader.readString();
    final filePath = reader.readString();
    final tempFilePath = reader.readString();
    final totalBytes = reader.readInt();
    final downloadedBytes = reader.readInt();
    final progress = reader.readDouble();
    final status = reader.readString();
    final errorMessage = reader.readString();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());
    final isM3u8 = reader.readBool();
    final headersMap = reader.readMap();
    final headers = headersMap.map((k, v) => MapEntry(k.toString(), v.toString()));
    final videoTitle = reader.readString();
    final coverUrl = reader.readString();
    final episodeInfo = reader.readString();
    final currentSegmentIndex = reader.readInt();
    final totalSegments = reader.readInt();
    final source = reader.readString();
    final sourceId = reader.readString();

    return DownloadTaskRecord(
      taskId: taskId,
      url: url,
      fileName: fileName,
      filePath: filePath,
      tempFilePath: tempFilePath,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      progress: progress,
      status: status,
      errorMessage: errorMessage.isEmpty ? null : errorMessage,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isM3u8: isM3u8,
      headers: headers.isEmpty ? null : headers,
      videoTitle: videoTitle.isEmpty ? null : videoTitle,
      coverUrl: coverUrl.isEmpty ? null : coverUrl,
      episodeInfo: episodeInfo.isEmpty ? null : episodeInfo,
      currentSegmentIndex: currentSegmentIndex < 0 ? null : currentSegmentIndex,
      totalSegments: totalSegments < 0 ? null : totalSegments,
      source: source.isEmpty ? null : source,
      sourceId: sourceId.isEmpty ? null : sourceId,
    );
  }
}
