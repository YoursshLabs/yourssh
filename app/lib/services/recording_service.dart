import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'audit_redactor.dart';

class RecordingService {
  RecordingService({this.flushDelay = const Duration(milliseconds: 500)});

  /// Max time a redacted recording's partial line (no newline yet) sits
  /// buffered before being flushed — bounds latency and buffer growth for
  /// TUI output that rarely prints newlines.
  final Duration flushDelay;

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
    bool redact = false,
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
        redact: redact,
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
    if (!rec.redact) {
      _writeEvent(rec, data); // legacy path: one raw event per chunk
      return;
    }
    rec.pending.write(data);
    final buffered = rec.pending.toString();
    // Split at the LAST newline: the complete portion is redacted and
    // written as one event; the partial tail stays buffered so a secret
    // straddling chunks can still join up before matching.
    final lastNl = buffered.lastIndexOf('\n');
    if (lastNl >= 0) {
      rec.pending.clear();
      rec.pending.write(buffered.substring(lastNl + 1));
      _writeEvent(rec, AuditRedactor.redact(buffered.substring(0, lastNl + 1)));
    }
    if (rec.pending.isEmpty) {
      rec.flushTimer?.cancel();
      rec.flushTimer = null;
    } else {
      // Start-once, no debounce: continuous TUI output without newlines
      // must still flush at most flushDelay after the first buffered byte.
      rec.flushTimer ??= Timer(flushDelay, () => _flushPending(sessionId));
    }
  }

  void _writeEvent(_ActiveRecording rec, String data) {
    final elapsed = rec.stopwatch.elapsedMicroseconds / 1000000.0;
    rec.sink.writeln(jsonEncode([elapsed, 'o', data]));
  }

  void _flushPending(String sessionId) {
    final rec = _active[sessionId];
    if (rec == null) return; // stopped while the timer was in flight
    rec.flushTimer = null;
    if (rec.pending.isEmpty) return;
    final text = rec.pending.toString();
    rec.pending.clear();
    _writeEvent(rec, AuditRedactor.redact(text));
  }

  Future<String?> stopRecording(String sessionId) async {
    final rec = _active.remove(sessionId);
    if (rec == null) return null;
    rec.flushTimer?.cancel();
    rec.flushTimer = null;
    if (rec.pending.isNotEmpty) {
      _writeEvent(rec, AuditRedactor.redact(rec.pending.toString()));
      rec.pending.clear();
    }
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
  final bool redact;
  final StringBuffer pending = StringBuffer();
  Timer? flushTimer;

  _ActiveRecording({
    required this.sink,
    required this.stopwatch,
    required this.filePath,
    required this.redact,
  });
}
