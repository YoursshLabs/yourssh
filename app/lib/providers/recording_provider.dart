import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/recording_entry.dart';
import '../models/ssh_session.dart';
import '../services/recording_service.dart';

class RecordingProvider extends ChangeNotifier {
  final RecordingService _service;
  final String Function() getPath;

  final List<RecordingEntry> _recordings = [];
  final Set<String> _activeIds = {};

  RecordingProvider(this._service, {required this.getPath});

  List<RecordingEntry> get recordings => List.unmodifiable(_recordings);

  Map<String, List<RecordingEntry>> get groupedRecordings {
    final map = <String, List<RecordingEntry>>{};
    for (final r in _recordings) {
      map.putIfAbsent(r.hostTitle, () => []).add(r);
    }
    return map;
  }

  bool isRecording(String sessionId) => _activeIds.contains(sessionId);

  Future<void> startRecording(SshSession session) async {
    if (_activeIds.contains(session.id)) return;

    final basePath = getPath();
    final hostFolder = '${session.host.username}@${session.host.host}';
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
        title: '${session.host.username}@${session.host.host}',
      );
      notifyListeners();
    } catch (_) {
      _activeIds.remove(session.id);
      notifyListeners();
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

    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.cast')) {
        files.add(entity);
      }
    }

    _recordings
      ..clear()
      ..addAll(files.map((f) => RecordingEntry.fromPath(f.path)));
    _recordings.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    notifyListeners();
  }

  Future<void> deleteRecording(String filePath) async {
    await File(filePath).delete();
    _recordings.removeWhere((r) => r.filePath == filePath);
    notifyListeners();
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
