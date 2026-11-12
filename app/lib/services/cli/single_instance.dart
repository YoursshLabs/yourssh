import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_handlers.dart';
import 'cli_listener.dart';
import 'cli_server.dart';

/// The CLI endpoint for this machine. Uses the same resolve() arguments as
/// the `yourssh` CLI (R10): the uid on macOS/Linux, the user SID on Windows
/// (`%LOCALAPPDATA%\YourSSH\run`, `\\.\pipe\yourssh-cli-<SID>`).
CliEndpoint resolveCliEndpoint() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return CliEndpoint.resolve(
      os: 'windows',
      env: env,
      home: env['USERPROFILE'] ?? '',
      userSid: currentUserSid(),
    );
  }
  return CliEndpoint.resolve(
    os: Platform.isMacOS ? 'macos' : 'linux',
    env: env,
    home: env['HOME'] ?? '',
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
  if (Platform.isWindows) return _tryOnceWindows(req, ep);
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

/// Windows: the shared pipe client, which checks that the pipe's server runs
/// as our user before the token is sent (R22). A pipe owned by someone else
/// counts as no instance: our own start then fails with CliEndpointInUse and
/// the app runs without the CLI.
Future<_Attempt> _tryOnceWindows(
    ({String cmd, Map<String, Object?> args}) req, CliEndpoint ep) async {
  final transport = WindowsPipeTransport(
      timeout: const Duration(seconds: 5),
      busyWait: const Duration(seconds: 1));
  // Everything inside the try: forwardToRunningInstance must never throw
  // (probe throws CliPermissionDenied for a pipe owned by another user).
  try {
    final token = await readToken(ep.tokenPath);
    if (token == null) {
      // Something answers but has not written its token yet: still starting.
      return await transport.probe(ep) ? _Attempt.retry : _Attempt.noInstance;
    }
    final line = await transport.roundTrip(
        ep,
        CliRequest(id: 'fwd', token: token, cmd: req.cmd, args: req.args)
            .encode());
    final resp = CliResponse.decode(line.trim());
    if (!resp.ok && resp.code == CliExit.denied) return _Attempt.retry;
    return _Attempt.answered;
  } catch (e) {
    debugPrint('single_instance: forward failed: $e');
    return _Attempt.noInstance;
  }
}

/// True when [code] (from RandomAccessFile.lock) means another holder:
/// Windows LockFileEx ERROR_LOCK_VIOLATION (33); POSIX fcntl EACCES (13) or
/// EAGAIN (11 Linux / 35 macOS).
bool isLockBusyError(int? code, {required bool windows}) {
  if (code == null) return false;
  return windows ? code == 33 : (code == 13 || code == 11 || code == 35);
}

/// Paths whose lock this process holds. POSIX record locks (what dart:io
/// uses on macOS/Linux) never conflict within one process, so in-process
/// contention is tracked here (Windows LockFileEx would also catch it).
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
    // append: never truncates a file another process holds locked.
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException catch (e) {
      await file.close();
      if (isLockBusyError(e.osError?.errorCode, windows: Platform.isWindows)) {
        return null; // somebody else holds it
      }
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

  /// Best effort and idempotent. Files are removed synchronously (before the
  /// first await) so a closing process gets them done even if it exits right
  /// after. macOS/Linux release the lock then too. On Windows the lock is
  /// released only after the listener has closed every pipe instance:
  /// a relaunch in between would take the lock and then fail its FIRST
  /// instance with CliEndpointInUse (the OS drops the lock at exit anyway).
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    // A named pipe has no file to remove: it goes with its last handle.
    for (final path in [if (!Platform.isWindows) _ep.address, _ep.tokenPath]) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // Already gone.
      }
    }
    if (!Platform.isWindows) _lock.release();
    try {
      await _listener.stop();
    } catch (e) {
      debugPrint('single_instance: stop failed: $e');
    } finally {
      if (Platform.isWindows) _lock.release();
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
/// replaced) or create the named pipe, then app.path (best effort; the
/// Windows and Linux CLIs start the app from it).
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
