import 'dart:io';

class RecordingEntry {
  final String filePath;
  final String hostTitle;
  final DateTime recordedAt;
  final Duration? duration;
  final int? fileSize;

  const RecordingEntry({
    required this.filePath,
    required this.hostTitle,
    required this.recordedAt,
    this.duration,
    this.fileSize,
  });

  String get fileName => filePath.split(Platform.pathSeparator).last;

  /// Builds an entry from a path without touching the filesystem. Use
  /// [fromPathWithStat] (async) when you need [fileSize] populated — callers
  /// listing many recordings should not block the UI thread on lengthSync().
  static RecordingEntry fromPath(String filePath, {int? fileSize}) {
    final segments = filePath.split(Platform.pathSeparator);
    final hostTitle = segments.length >= 2 ? segments[segments.length - 2] : 'unknown';
    final name = segments.last;

    DateTime recordedAt;
    try {
      final withoutExt = name.endsWith('.cast') ? name.substring(0, name.length - 5) : name;
      final withoutPrefix = withoutExt.startsWith('session_')
          ? withoutExt.substring('session_'.length)
          : withoutExt;
      final parts = withoutPrefix.split('_');
      if (parts.length == 2) {
        final timePart = parts[1].replaceAll('-', ':');
        recordedAt = DateTime.parse('${parts[0]}T$timePart');
      } else {
        recordedAt = DateTime.fromMillisecondsSinceEpoch(0);
      }
    } catch (_) {
      recordedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return RecordingEntry(
      filePath: filePath,
      hostTitle: hostTitle,
      recordedAt: recordedAt,
      fileSize: fileSize,
    );
  }

  static Future<RecordingEntry> fromPathWithStat(String filePath) async {
    final file = File(filePath);
    final size = await file.exists() ? await file.length() : null;
    return fromPath(filePath, fileSize: size);
  }
}
