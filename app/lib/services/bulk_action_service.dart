import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/bulk_result.dart';
import '../models/host.dart';

/// Cooperative cancellation for a bulk run: queued hosts are marked
/// cancelled; hosts already in flight run to completion and record their
/// real result (an SSH exec can't be aborted mid-flight).
class BulkCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// One local source (file or directory) for a bulk push, with its total
/// byte size pre-computed so per-host progress has a denominator.
class BulkPushSource {
  final String path;
  final bool isDirectory;
  final int bytes;
  const BulkPushSource(
      {required this.path, required this.isDirectory, required this.bytes});
  String get name => p.basename(path);
}

typedef BulkExecFn = Future<({String stdout, String stderr, int exitCode})>
    Function(Host host, String command);
typedef BulkUploadFileFn = Future<void> Function(
    Host host, String localPath, String remotePath,
    {void Function(int sent, int total)? onProgress});
/// Callers wrapping `SftpTransferService.uploadDirectory` must adapt the
/// signature (rename `remoteHost` → `host`, supply a no-op `onFileSkipped`,
/// pass `overwrite: true`).
typedef BulkUploadDirFn = Future<void> Function({
  required Host host,
  required String localDir,
  required String remoteDir,
  required void Function(String filePath, int bytes, int total) onProgress,
  required bool Function() isCancelled,
});
typedef BulkMkdirFn = Future<void> Function(Host host, String path);

/// Parallel engine behind the bulk action panel: bounded-concurrency worker
/// pool with per-host failure isolation. Pure orchestration over injected
/// per-host operations — tests inject fakes; the dialogs inject
/// `SshService.exec`, `SftpTransferService` uploads, and
/// `SftpFileOpsService.mkdir`.
class BulkActionService {
  final BulkExecFn? _exec;
  final BulkUploadFileFn? _uploadFile;
  final BulkUploadDirFn? _uploadDirectory;
  final BulkMkdirFn? _mkdir;

  BulkActionService({
    BulkExecFn? exec,
    BulkUploadFileFn? uploadFile,
    BulkUploadDirFn? uploadDirectory,
    BulkMkdirFn? mkdir,
  })  : _exec = exec, // ignore: prefer_initializing_formals
        _uploadFile = uploadFile, // ignore: prefer_initializing_formals
        _uploadDirectory = uploadDirectory, // ignore: prefer_initializing_formals
        _mkdir = mkdir; // ignore: prefer_initializing_formals

  /// Runs [command] on every host, at most [maxConcurrent] in flight.
  /// Emits a `running` update when a host is picked up and exactly one
  /// terminal update (`success`/`failed`/`cancelled`) when it finishes.
  Future<void> runCommand(
    List<Host> hosts,
    String command, {
    required void Function(BulkHostResult) onUpdate,
    required BulkCancelToken token,
    int maxConcurrent = 6,
    Duration perHostTimeout = const Duration(seconds: 30),
  }) {
    final exec = _exec;
    if (exec == null) throw StateError('BulkActionService: exec not wired');
    return _pool(hosts, maxConcurrent, (host) async {
      if (token.isCancelled) {
        onUpdate(BulkHostResult(host: host, status: BulkHostStatus.cancelled));
        return;
      }
      onUpdate(BulkHostResult(host: host, status: BulkHostStatus.running));
      final sw = Stopwatch()..start();
      try {
        final r = await exec(host, command).timeout(perHostTimeout);
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.success,
          exitCode: r.exitCode,
          stdout: r.stdout,
          stderr: r.stderr,
          elapsed: sw.elapsed,
        ));
      } on TimeoutException {
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.failed,
          error: 'Timed out after ${perHostTimeout.inSeconds}s',
          elapsed: sw.elapsed,
        ));
      } catch (e) {
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.failed,
          error: e.toString(),
          elapsed: sw.elapsed,
        ));
      }
    });
  }

  /// Pushes every source to [remoteDir] on every host (hosts in parallel,
  /// sources within a host sequential). Emits `running` updates with
  /// cumulative [BulkHostResult.bytesTransferred] and one terminal update.
  Future<void> pushFiles(
    List<Host> hosts,
    List<BulkPushSource> sources,
    String remoteDir, {
    required void Function(BulkHostResult) onUpdate,
    required BulkCancelToken token,
    int maxConcurrent = 4,
  }) {
    final uploadFile = _uploadFile;
    final uploadDirectory = _uploadDirectory;
    final mkdir = _mkdir;
    if (uploadFile == null || uploadDirectory == null || mkdir == null) {
      throw StateError('BulkActionService: upload/mkdir not wired');
    }
    final total = sources.fold(0, (a, s) => a + s.bytes);
    return _pool(hosts, maxConcurrent, (host) async {
      if (token.isCancelled) {
        onUpdate(BulkHostResult(
            host: host, status: BulkHostStatus.cancelled, totalBytes: total));
        return;
      }
      onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.running,
          bytesTransferred: 0,
          totalBytes: total));
      final sw = Stopwatch()..start();
      var done = 0; // bytes of fully finished sources
      void progress(int withinCurrent) => onUpdate(BulkHostResult(
            host: host,
            status: BulkHostStatus.running,
            bytesTransferred: done + withinCurrent,
            totalBytes: total,
          ));
      try {
        await ensureRemoteDir((path) => mkdir(host, path), remoteDir);
        for (final src in sources) {
          if (token.isCancelled) break;
          final dest = p.posix.join(remoteDir, src.name);
          if (src.isDirectory) {
            var dirSent = 0;
            final perFile = <String, int>{};
            await uploadDirectory(
              host: host,
              localDir: src.path,
              remoteDir: dest,
              onProgress: (filePath, bytes, _) {
                dirSent += bytes - (perFile[filePath] ?? 0);
                perFile[filePath] = bytes;
                progress(dirSent);
              },
              isCancelled: () => token.isCancelled,
            );
          } else {
            await uploadFile(host, src.path, dest,
                onProgress: (sent, _) => progress(sent));
          }
          done += src.bytes;
        }
        final cancelled = token.isCancelled && (done < total || sources.isEmpty);
        onUpdate(BulkHostResult(
          host: host,
          status:
              cancelled ? BulkHostStatus.cancelled : BulkHostStatus.success,
          bytesTransferred: done,
          totalBytes: total,
          elapsed: sw.elapsed,
        ));
      } catch (e) {
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.failed,
          error: e.toString(),
          bytesTransferred: done,
          totalBytes: total,
          elapsed: sw.elapsed,
        ));
      }
    });
  }

  /// Creates [remoteDir] and any missing parents with single-level [mkdir]
  /// calls. Errors are swallowed: "already exists" is the common case, and
  /// a dir that truly failed to create surfaces as the upload error that
  /// follows immediately.
  static Future<void> ensureRemoteDir(
      Future<void> Function(String path) mkdir, String remoteDir) async {
    final parts = p.posix.split(remoteDir);
    var current = '';
    for (final part in parts) {
      current = current.isEmpty ? part : p.posix.join(current, part);
      if (current == '/') continue;
      try {
        await mkdir(current);
      } catch (_) {
        // exists, or the upload right after will surface the real error
      }
    }
  }

  /// Resolves picked paths into [BulkPushSource]s with pre-computed sizes
  /// (the denominator for progress). Directories are walked recursively.
  /// Sizes are snapshotted at resolution time; concurrent modifications
  /// affect progress accuracy, not correctness.
  static Future<List<BulkPushSource>> resolveSources(
      List<String> paths) async {
    final out = <BulkPushSource>[];
    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path)) {
        var bytes = 0;
        await for (final e
            in Directory(path).list(recursive: true, followLinks: false)) {
          if (e is File) bytes += await e.length();
        }
        out.add(BulkPushSource(path: path, isDirectory: true, bytes: bytes));
      } else {
        out.add(BulkPushSource(
            path: path, isDirectory: false, bytes: await File(path).length()));
      }
    }
    return out;
  }

  /// Runs [body] for every host with at most [maxConcurrent] in flight.
  /// Dequeue happens synchronously at loop top (single-threaded event loop),
  /// so no host is ever picked up twice.
  Future<void> _pool(List<Host> hosts, int maxConcurrent,
      Future<void> Function(Host host) body) async {
    final queue = List.of(hosts);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        await body(queue.removeAt(0));
      }
    }

    final n = maxConcurrent.clamp(1, hosts.isEmpty ? 1 : hosts.length);
    await Future.wait([for (var i = 0; i < n; i++) worker()]);
  }
}
