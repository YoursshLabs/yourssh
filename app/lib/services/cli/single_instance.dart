import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_handlers.dart';
import 'cli_listener.dart';
import 'cli_server.dart';
import 'peer_cred.dart';

/// The CLI endpoint for this machine, or null where it is not supported yet
/// (Windows named pipes arrive in a later task).
CliEndpoint? resolveCliEndpoint() {
  if (Platform.isWindows) return null;
  return CliEndpoint.resolve(
    os: Platform.isMacOS ? 'macos' : 'linux',
    env: Platform.environment,
    home: Platform.environment['HOME'] ?? '',
    uid: currentUid(),
  );
}

/// Maps a second launch's argv to a request: a `yourssh://` URL opens that
/// host; anything else just raises the running window.
({String cmd, Map<String, Object?> args}) requestForArgs(List<String> args) {
  for (final a in args) {
    if (a.toLowerCase().startsWith('yourssh://')) {
      return (cmd: 'open', args: {'url': a});
    }
  }
  return (cmd: 'activate', args: const <String, Object?>{});
}

/// Hands this launch's request to an already-running instance. True when one
/// answered — with ok OR an error such as an unknown host: either way the
/// request reached the owner, so no second app may start. False when nothing
/// answered. Never throws.
///
/// A denied reply (the owner has bound but not rewritten the token yet) is
/// retried until [deadline]. "Nobody listening" returns at once unless
/// [retryUnreachable] (the caller knows an owner exists but may still be
/// starting).
Future<bool> forwardToRunningInstance(List<String> args, CliEndpoint ep,
    {Duration deadline = const Duration(seconds: 3),
    bool retryUnreachable = false}) async {
  if (Platform.isWindows) return false;
  final req = requestForArgs(args);
  final end = DateTime.now().add(deadline);
  while (true) {
    final r = await _tryOnce(req, ep);
    if (r == _Attempt.answered) return true;
    if (r == _Attempt.noInstance && !retryUnreachable) return false;
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

enum _Attempt { answered, noInstance, retry }

Future<_Attempt> _tryOnce(
    ({String cmd, Map<String, Object?> args}) req, CliEndpoint ep) async {
  Socket socket;
  try {
    socket = await Socket.connect(
            InternetAddress(ep.address, type: InternetAddressType.unix), 0)
        .timeout(const Duration(seconds: 1));
  } on SocketException {
    return _Attempt.noInstance;
  } on TimeoutException {
    return _Attempt.noInstance;
  }
  try {
    final token = await readToken(ep.tokenPath);
    if (token == null) return _Attempt.retry;
    socket.write(CliRequest(
            id: 'fwd', token: token, cmd: req.cmd, args: req.args)
        .encode());
    socket.write('\n');
    await socket.flush();
    final line = await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 5));
    final resp = CliResponse.decode(line.trim());
    if (!resp.ok && resp.code == CliExit.denied) return _Attempt.retry;
    return _Attempt.answered;
  } catch (e) {
    debugPrint('single_instance: forward failed: $e');
    return _Attempt.noInstance;
  } finally {
    socket.destroy();
  }
}

/// Paths whose lock this process holds. POSIX record locks (what dart:io
/// uses) never conflict within one process, so in-process contention is
/// tracked here.
final Set<String> _heldLocks = {};

/// Exclusive, non-blocking lock on `<runDir>/cli.lock`, held for the app's
/// lifetime: whoever holds it owns the CLI endpoint.
class _InstanceLock {
  _InstanceLock._(this._path, this._file);
  final String _path;
  final RandomAccessFile _file;

  /// Null when another instance holds it. Throws on any other I/O error.
  static Future<_InstanceLock?> tryAcquire(String runDir) async {
    final path = File('$runDir/cli.lock').absolute.path;
    if (_heldLocks.contains(path)) return null;
    final file = await File(path).open(mode: FileMode.write);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException catch (e) {
      await file.close();
      final code = e.osError?.errorCode;
      // EACCES (13), EAGAIN (11 Linux / 35 macOS): somebody else holds it.
      if (code == 13 || code == 11 || code == 35) return null;
      rethrow;
    }
    // Re-check: another start in this process may have won while we awaited.
    if (!_heldLocks.add(path)) {
      await file.close();
      return null;
    }
    return _InstanceLock._(path, file);
  }

  void release() {
    _heldLocks.remove(_path);
    try {
      _file.unlockSync();
    } catch (_) {}
    try {
      _file.closeSync();
    } catch (_) {}
  }
}

/// The running CLI endpoint: listener + lock + files. [stop] is the window
/// close cleanup; after a crash the leftovers are harmless (the next owner
/// takes the lock and replaces the stale socket).
class CliEndpointOwner {
  CliEndpointOwner._(this._ep, this._listener, this._lock);
  final CliEndpoint _ep;
  final CliListener _listener;
  final _InstanceLock _lock;
  bool _stopped = false;

  /// Best effort and idempotent. Files are removed and the lock released
  /// synchronously (before the first await) so a closing process gets them
  /// done even if it exits right after.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final path in [_ep.address, _ep.tokenPath]) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Already gone.
      }
    }
    _lock.release();
    try {
      await _listener.stop();
    } catch (e) {
      debugPrint('single_instance: stop failed: $e');
    }
  }
}

/// Takes ownership of the CLI endpoint, or hands [args] to the instance that
/// owns it.
///
/// Returns the owner, or null when another instance holds the lock — in that
/// case the request was forwarded (retrying for [forwardRetry] while the
/// owner may still be starting) and the caller should exit; no second
/// endpoint is ever started. Throws when the endpoint cannot be set up (the
/// caller runs without the CLI).
///
/// Lock holder order: token, then bind the socket (a stale socket file is
/// replaced), then app.path (best effort).
Future<CliEndpointOwner?> startCliEndpoint(
    CliEndpoint ep, CliHandlers handlers, List<String> args,
    {Duration forwardRetry = const Duration(seconds: 5)}) async {
  final token = generateToken();
  final listener =
      createCliListener(ep, CliServer(handlers: handlers, token: token));
  await listener.prepare();
  final lock = await _InstanceLock.tryAcquire(ep.runDir);
  if (lock == null) {
    await forwardToRunningInstance(args, ep,
        deadline: forwardRetry, retryUnreachable: true);
    return null;
  }
  try {
    await writeToken(ep.runDir, token: token);
    await listener.start();
  } catch (_) {
    lock.release();
    await listener.stop();
    rethrow;
  }
  try {
    await File('${ep.runDir}/app.path')
        .writeAsString(Platform.resolvedExecutable, flush: true);
  } catch (e) {
    debugPrint('single_instance: cannot write app.path: $e');
  }
  return CliEndpointOwner._(ep, listener, lock);
}
