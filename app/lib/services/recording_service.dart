import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RecordingService {
  final Map<String, _ActiveRecording> _active = {};

  bool isRecording(String sessionId) => _active.containsKey(sessionId);

  Future<void> startRecording(
    String sessionId, {
    required String filePath,
    required int width,
    required int height,
    required String title,
  }) async {
    if (_active.containsKey(sessionId)) return;
    IOSink? sink;
    try {
      final dir = File(filePath).parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      sink = File(filePath).openWrite(mode: FileMode.write);
      final header = {
        'version': 2,
        'width': width,
        'height': height,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'title': title,
      };
      sink.writeln(jsonEncode(header));
      _active[sessionId] = _ActiveRecording(
        sink: sink,
        stopwatch: Stopwatch()..start(),
        filePath: filePath,
      );
    } catch (_) {
      await sink?.close();
    }
  }

  void writeOutput(String sessionId, String data) {
    final rec = _active[sessionId];
    if (rec == null) return;
    final elapsed = rec.stopwatch.elapsedMicroseconds / 1000000.0;
    rec.sink.writeln(jsonEncode([elapsed, 'o', data]));
  }

  Future<String?> stopRecording(String sessionId) async {
    final rec = _active.remove(sessionId);
    if (rec == null) return null;
    rec.stopwatch.stop();
    await rec.sink.flush();
    await rec.sink.close();
    return rec.filePath;
  }

  void onShellClosed(String sessionId) {
    if (isRecording(sessionId)) {
      unawaited(stopRecording(sessionId));
    }
  }
}

class _ActiveRecording {
  final IOSink sink;
  final Stopwatch stopwatch;
  final String filePath;

  _ActiveRecording({
    required this.sink,
    required this.stopwatch,
    required this.filePath,
  });
}
