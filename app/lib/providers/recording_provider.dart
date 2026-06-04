import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/recording_entry.dart';
import '../models/terminal_session.dart';
import '../services/recording_service.dart';

class RecordingProvider extends ChangeNotifier {
  final RecordingService _service;
  final String Function() getPath;

  /// Invoked when a recording fails to start (e.g., auto-record on connect).
  /// The UI layer should surface this — silently dropping it makes `autoRecord`
  /// look like it turned itself off, which is the bug report we keep getting.
  void Function(TerminalSession session, Object error)? onStartFailed;

  final List<RecordingEntry> _recordings = [];
  final Set<String> _activeIds = {};

  RecordingProvider(this._service, {required this.getPath}) {
    // Recordings can stop without going through this provider (shell exit /
    // disconnect → SshService/LocalShellService → RecordingService
    // .onShellClosed). Sync our state so the REC indicator clears and the
    // finalized .cast shows up in the library.
    _service.onRecordingStopped = (sessionId) {
      if (_activeIds.remove(sessionId)) {
        notifyListeners();
        unawaited(refreshLibrary());
      }
    };
  }

  List<RecordingEntry> get recordings => List.unmodifiable(_recordings);

  Map<String, List<RecordingEntry>> get groupedRecordings {
    final map = <String, List<RecordingEntry>>{};
    for (final r in _recordings) {
      map.putIfAbsent(r.hostTitle, () => []).add(r);
    }
    return map;
  }

  bool isRecording(String sessionId) => _activeIds.contains(sessionId);

  Future<void> startRecording(TerminalSession session) async {
    if (_activeIds.contains(session.id)) return;

    final basePath = getPath();
    // From the interface, not a type check — a future third session type
    // names its own folder/title instead of being misfiled as "local".
    final hostFolder = session.recordingFolder;
    final title = session.recordingTitle;
    final now = DateTime.now();
    final ts = '${now.year}-${_pad(now.month)}-${_pad(now.day)}'
        '_${_pad(now.hour)}-${_pad(now.minute)}-${_pad(now.second)}';
    final filePath = '$basePath/$hostFolder/session_$ts.cast';

    _activeIds.add(session.id);
    try {
      await _service.startRecording(
        session.id,
        filePath: filePath,
        width: session.terminal.viewWidth,
        height: session.terminal.viewHeight,
        title: title,
      );
      notifyListeners();
    } catch (e) {
      _activeIds.remove(session.id);
      notifyListeners();
      onStartFailed?.call(session, e);
    }
  }

  Future<void> stopRecording(String sessionId) async {
    final path = await _service.stopRecording(sessionId);
    _activeIds.remove(sessionId);
    if (path != null) await refreshLibrary();
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    final basePath = getPath();
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      _recordings.clear();
      notifyListeners();
      return;
    }

    final entries = <RecordingEntry>[];
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.cast')) {
          try {
            final size = await entity.length();
            entries.add(RecordingEntry.fromPath(entity.path, fileSize: size));
          } catch (_) {
            entries.add(RecordingEntry.fromPath(entity.path));
          }
        }
      }
    } on FileSystemException catch (e) {
      // The recordings folder can vanish mid-scan (user deleted it, temp
      // cleanup). Keep whatever was collected instead of crashing the
      // background refresh.
      debugPrint('[RecordingProvider] refreshLibrary aborted mid-scan: $e');
    }

    _recordings
      ..clear()
      ..addAll(entries);
    _recordings.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    notifyListeners();
  }

  Future<void> deleteRecording(String filePath) async {
    final file = File(filePath);
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      // File still appears in the library until next refresh — surface the
      // failure via the caller (UI) rather than silently keeping the entry.
      rethrow;
    }
    _recordings.removeWhere((r) => r.filePath == filePath);
    notifyListeners();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
