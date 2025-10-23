class EpgProgram {
  final String channelId;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? description;

  EpgProgram({
    required this.channelId,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.description,
  });

  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  double get progress {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    
    final total = endTime.difference(startTime).inSeconds;
    final elapsed = now.difference(startTime).inSeconds;
    return elapsed / total;
  }

  String get timeRange {
    final start = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
    final end = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
    return '$start - $end';
  }

  factory EpgProgram.fromXml(Map<String, dynamic> data) {
    return EpgProgram(
      channelId: data['channel'] ?? '',
      title: data['title'] ?? '',
      startTime: DateTime.parse(data['start']),
      endTime: DateTime.parse(data['stop']),
      description: data['desc'],
    );
  }
}
