import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class RecordingService {
  final Map<String, _ActiveRecording> _active = {};

  /// Fired whenever a recording stops, including stops the provider did not
  /// initiate (shell exit/disconnect via [onShellClosed]). Without this the
  /// provider's REC indicator stays red while [writeOutput] silently no-ops.
  /// Wired by RecordingProvider's constructor.
  void Function(String sessionId)? onRecordingStopped;

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
    } catch (e) {
      debugPrint('[RecordingService] startRecording $sessionId failed: $e');
      await sink?.close();
      rethrow;
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
    // Notify as soon as the recording leaves _active — the sink flush below
    // is async and the UI must not show a red REC indicator meanwhile.
    onRecordingStopped?.call(sessionId);
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
