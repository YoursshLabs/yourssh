// app/lib/services/external_edit_service.dart
import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart' show launchUrl;

import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../util/app_launcher.dart';
import 'sftp_transfer_service.dart';
import '../util/private_temp.dart';

typedef ExternalLauncher = Future<bool> Function(Uri uri);
typedef AppLauncher = Future<bool> Function(Uri uri, String? appPath);

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
    AppLauncher? appLauncher,
    String? platform,
    this.pollInterval = const Duration(seconds: 2),
  })  : _launch = launcher ?? launchUrl,
        _appLaunch = appLauncher,
        _platform = platform ?? Platform.operatingSystem;

  final SftpTransferService _transferService;
  final ExternalLauncher _launch;
  final AppLauncher? _appLaunch;
  final String _platform;
  final Duration pollInterval;

  /// Called after a changed file was uploaded back to the server.
  void Function(String fileName)? onUploaded;

  /// Called when uploading a changed file failed; watching continues so the
  /// next save retries.
  void Function(String fileName, Object error)? onUploadError;

  final List<_WatchSession> _sessions = [];
  final Set<Directory> _tempDirs = {};

  int get activeWatchCount => _sessions.length;

  /// Downloads [entry], opens it with the OS default app and watches the
  /// local copy, uploading it back to [entry.path] whenever it changes.
  ///
  /// Throws [ExternalEditException] when the download or launch fails.
  Future<void> openExternal(Host host, SftpEntry entry) async {
    // The OS default handler would run a server-chosen executable type.
    if (isExecutableExtension(entry.name, _platform)) {
      throw ExternalEditException(
          'Not opening ${entry.name}: this file type can run code. '
          'Download it instead and inspect it first.');
    }
    final localFile = await _prepareLocalFile(host, entry);
    final launched = _appLaunch != null
        ? await _appLaunch(Uri.file(localFile.path), null)
        : await _launch(Uri.file(localFile.path));
    if (!launched) {
      throw ExternalEditException('No application found to open ${entry.name}');
    }
    _startWatcher(host, entry, localFile);
  }

  /// Like [openExternal] but launches with a specific application [appPath]
  /// instead of the OS default.
  Future<void> openExternalWith(
      Host host, SftpEntry entry, String appPath) async {
    final localFile = await _prepareLocalFile(host, entry);
    final launched = _appLaunch != null
        ? await _appLaunch(Uri.file(localFile.path), appPath)
        : await _launchWithApp(localFile.path, appPath);
    if (!launched) {
      throw ExternalEditException(
          'Failed to open ${entry.name} with $appPath');
    }
    _startWatcher(host, entry, localFile);
  }

  Future<File> _prepareLocalFile(Host host, SftpEntry entry) async {
    final tmpPath = await _transferService.downloadToTemp(host, entry);
    if (tmpPath == null) {
      throw ExternalEditException('Download failed for ${entry.name}');
    }
    // downloadToTemp hands back a file in its own random per-download dir.
    final file = File(tmpPath);
    final sessionDir = file.parent;
    _tempDirs.add(sessionDir);
    await restrictToOwner(dir: sessionDir, file: file);
    return file;
  }

  void _startWatcher(Host host, SftpEntry entry, File localFile) {
    // Re-opening the same remote file replaces its watcher rather than stacking
    // a second timer that polls the same path for the lifetime of the screen.
    _stopWatching(host.id, entry.path);
    final session = _WatchSession(
      host: host,
      entry: entry,
      file: localFile,
      lastModified: localFile.lastModifiedSync(),
    );
    session.timer = Timer.periodic(pollInterval, (_) => _poll(session));
    _sessions.add(session);
  }

  void _stopWatching(String hostId, String remotePath) {
    _sessions.removeWhere((s) {
      if (s.host.id == hostId && s.entry.path == remotePath) {
        s.timer?.cancel();
        return true;
      }
      return false;
    });
  }

  Future<bool> _launchWithApp(String filePath, String appPath) =>
      launchFileWithApp(filePath, appPath);

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
    for (final dir in _tempDirs) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Already gone or locked by the editor; nothing more to do.
      }
    }
    _tempDirs.clear();
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
