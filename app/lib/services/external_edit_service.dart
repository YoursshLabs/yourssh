// app/lib/services/external_edit_service.dart
import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart' show launchUrl;

import '../models/host.dart';
import '../models/sftp_entry.dart';
import 'sftp_transfer_service.dart';

typedef ExternalLauncher = Future<bool> Function(Uri uri);

class ExternalEditException implements Exception {
  ExternalEditException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Opens remote files with the OS default application and uploads them back
/// when the external app saves changes (WinSCP-style external editing).
///
/// Watching polls mtime instead of using filesystem events: many editors
/// save atomically via rename-over, which silently breaks inotify/FSEvents
/// watches on the original path. Watchers run until [dispose].
class ExternalEditService {
  ExternalEditService(
    this._transferService, {
    ExternalLauncher? launcher,
    this.pollInterval = const Duration(seconds: 2),
  }) : _launch = launcher ?? launchUrl;

  final SftpTransferService _transferService;
  final ExternalLauncher _launch;
  final Duration pollInterval;

  /// Called after a changed file was uploaded back to the server.
  void Function(String fileName)? onUploaded;

  /// Called when uploading a changed file failed; watching continues so the
  /// next save retries.
  void Function(String fileName, Object error)? onUploadError;

  final List<_WatchSession> _sessions = [];
  int _sessionCounter = 0;

  int get activeWatchCount => _sessions.length;

  /// Downloads [entry], opens it with the OS default app and watches the
  /// local copy, uploading it back to [entry.path] whenever it changes.
  ///
  /// Throws [ExternalEditException] when the download or launch fails.
  Future<void> openExternal(Host host, SftpEntry entry) async {
    final tmpPath = await _transferService.downloadToTemp(host, entry);
    if (tmpPath == null) {
      throw ExternalEditException('Download failed for ${entry.name}');
    }
    // Move into a per-session directory so concurrent edits of equally
    // named files cannot clobber each other in the shared temp dir.
    final sessionDir = Directory(
        '${File(tmpPath).parent.path}/yourssh_edit/${_sessionCounter++}');
    await sessionDir.create(recursive: true);
    final localFile =
        await File(tmpPath).rename('${sessionDir.path}/${entry.name}');

    if (!await _launch(Uri.file(localFile.path))) {
      throw ExternalEditException(
          'No application found to open ${entry.name}');
    }

    final session = _WatchSession(
      host: host,
      entry: entry,
      file: localFile,
      lastModified: localFile.lastModifiedSync(),
    );
    session.timer = Timer.periodic(pollInterval, (_) => _poll(session));
    _sessions.add(session);
  }

  Future<void> _poll(_WatchSession session) async {
    if (session.uploading) return;
    final DateTime mtime;
    try {
      mtime = session.file.lastModifiedSync();
    } on FileSystemException {
      return; // file briefly missing during an atomic save — retry next tick
    }
    if (mtime.isAtSameMomentAs(session.lastModified)) return;
    session.lastModified = mtime;
    session.uploading = true;
    try {
      await _transferService.uploadFile(
          session.host, session.file.path, session.entry.path);
      onUploaded?.call(session.entry.name);
    } catch (e) {
      onUploadError?.call(session.entry.name, e);
    } finally {
      session.uploading = false;
    }
  }

  void dispose() {
    for (final session in _sessions) {
      session.timer?.cancel();
    }
    _sessions.clear();
  }
}

class _WatchSession {
  _WatchSession({
    required this.host,
    required this.entry,
    required this.file,
    required this.lastModified,
  });

  final Host host;
  final SftpEntry entry;
  final File file;
  DateTime lastModified;
  Timer? timer;
  bool uploading = false;
}
