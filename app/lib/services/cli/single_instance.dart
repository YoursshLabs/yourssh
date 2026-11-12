import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kReleaseMode, visibleForTesting;
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_listener.dart';
import 'cli_listener_unix.dart' show isPrivateRunDir;
import 'cli_server.dart';
import 'peer_cred.dart';

/// The CLI endpoint for this machine. Uses the same resolve() arguments as
/// the `yourssh` CLI (R10): the uid on macOS/Linux, the user SID on Windows
/// (`%LOCALAPPDATA%\YourSSH\run`, `\\.\pipe\yourssh-cli-<SID>`).
///
/// A non-release build ([dev], e.g. `flutter run`) uses the separate dev
/// variant (`YourSSH-dev` run dir, `yourssh-cli-dev-<SID>` pipe), so it never
/// takes the installed app's lock or endpoint; the CLI reaches it with
/// `YOURSSH_DEV=1`.
CliEndpoint resolveCliEndpoint({bool dev = !kReleaseMode}) {
  final env = Platform.environment;
  if (Platform.isWindows) {
    return CliEndpoint.resolve(
      os: 'windows',
      env: env,
      home: env['USERPROFILE'] ?? '',
      userSid: currentUserSid(),
      dev: dev,
    );
  }
  return CliEndpoint.resolve(
    os: Platform.isMacOS ? 'macos' : 'linux',
    env: env,
    home: env['HOME'] ?? '',
    uid: currentUid(),
    dev: dev,
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

/// How long a forwarder waits for the owner's reply. Longer than the
/// server's ready gate, which can hold an `open` for up to
/// [CliServer.defaultReadyTimeout]; shorter would time out, retry and (before
/// the debounce moved behind the gate) open the URL twice.
const kForwardReplyTimeout = Duration(seconds: 20);

/// How long a losing second launch keeps retrying while the owner holds the
/// lock but has not bound its socket yet (it binds after the first frame):
/// as long as the owner's providers may take to load.
const kDefaultForwardRetry = CliServer.defaultReadyTimeout;

/// Hands this launch's request to an already-running instance. True when one
/// answered — with ok OR an error such as an unknown host: either way the
/// request reached the owner, so no second app may start. False when nothing
/// answered. Never throws.
///
/// A denied reply (the owner has bound but not rewritten the token yet) is
/// retried until [deadline]. "Nobody listening" returns at once unless
/// [retryUnreachable] (the caller knows an owner exists but may still be
/// starting).
///
/// A shared-temp run dir (the short fallback) must be ours and 0700, and the
/// socket's peer ([peerUid], `SO_PEERCRED` / `LOCAL_PEERCRED`) must be our
/// uid, before the token is read or anything is sent; otherwise nothing is
/// forwarded.
Future<bool> forwardToRunningInstance(List<String> args, CliEndpoint ep,
    {Duration deadline = const Duration(seconds: 3),
    bool retryUnreachable = false,
    @visibleForTesting int? Function(Socket socket) peerUid = peerUidOf,
    @visibleForTesting DateTime Function() clock = DateTime.now,
    @visibleForTesting
    Future<void> Function(Duration) delay = _sleep}) async {
  final req = requestForArgs(args);
  final end = clock().add(deadline);
  while (true) {
    final r = await _tryOnce(req, ep, peerUid);
    if (r == _Attempt.answered) return true;
    if (r == _Attempt.noInstance && !retryUnreachable) return false;
    if (clock().isAfter(end)) return false;
    await delay(const Duration(milliseconds: 100));
  }
}

Future<void> _sleep(Duration d) => Future<void>.delayed(d);

enum _Attempt { answered, noInstance, retry }

Future<_Attempt> _tryOnce(({String cmd, Map<String, Object?> args}) req,
    CliEndpoint ep, int? Function(Socket socket) peerUid) async {
  if (Platform.isWindows) return _tryOnceWindows(req, ep);
  if (ep.inSharedTemp && !await isPrivateRunDir(ep.runDir)) {
    debugPrint('single_instance: shared run dir is not ours/0700; '
        'not forwarding');
    return _Attempt.noInstance;
  }
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
    if (ep.inSharedTemp) {
      final peer = peerUid(socket);
      if (peer == null || peer != currentUid()) {
        debugPrint('single_instance: socket peer is not us; not forwarding');
        return _Attempt.noInstance;
      }
    }
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
        .timeout(kForwardReplyTimeout);
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
      timeout: kForwardReplyTimeout,
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
/// lifetime: whoever holds it is the single instance and owns the CLI
/// endpoint. Taken in main() before any start-up work.
class InstanceLock {
  InstanceLock._(this._path, this._file);
  final String _path;
  final RandomAccessFile _file;
  bool _released = false;

  /// Null when another instance holds it. Throws on any other I/O error.
  static Future<InstanceLock?> _tryAcquire(String runDir) async {
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
    return InstanceLock._(path, file);
  }

  /// Idempotent. The OS also drops the lock when the process exits.
  void release() {
    if (_released) return;
    _released = true;
    _heldLocks.remove(_path);
    try {
      _file.unlockSync();
    } catch (_) {}
    try {
      _file.closeSync();
    } catch (_) {}
  }
}

/// Creates the run dir (0700, shared-temp checks) and takes the
/// single-instance lock. Returns the lock, or null when another instance
/// holds it: then [args] was forwarded to it (retrying for [forwardRetry]
/// while it may still be starting) and the caller must exit before any
/// start-up work. Throws when the run dir or lock file cannot be set up
/// (the app then runs without the CLI).
Future<InstanceLock?> acquireInstanceLockOrForward(
    CliEndpoint ep, List<String> args,
    {Duration forwardRetry = kDefaultForwardRetry}) async {
  await prepareCliRunDir(ep);
  final lock = await InstanceLock._tryAcquire(ep.runDir);
  if (lock != null) return lock;
  await forwardToRunningInstance(args, ep,
      deadline: forwardRetry, retryUnreachable: true);
  return null;
}

/// The start-up gate main() runs before anything else (I1): a second launch
/// hands its request (URL or `activate`) to the running instance and exits
/// through [exitApp] before it loads plugins, starts port forwards, migrates
/// secrets, checks for updates or syncs.
///
/// 1. Something already answers on the endpoint → forward, exit.
/// 2. Otherwise take the lock; busy (the owner is still starting) →
///    forward with retry, exit.
///
/// Returns the endpoint and the held lock (kept for the app's lifetime; the
/// token, listener and app.path follow after the first frame), or null when
/// the endpoint cannot be resolved or set up — the app then starts without
/// the CLI. [exitApp] never returns; tests pass one that throws.
Future<({CliEndpoint endpoint, InstanceLock lock})?> claimSingleInstance(
  List<String> args, {
  CliEndpoint Function() resolve = resolveCliEndpoint,
  Never Function(int code) exitApp = exit,
  Duration forwardRetry = kDefaultForwardRetry,
}) async {
  final CliEndpoint ep;
  try {
    ep = resolve();
  } catch (e) {
    debugPrint('single_instance: no CLI endpoint: $e');
    return null;
  }
  var forwarded = false;
  try {
    forwarded = await forwardToRunningInstance(args, ep);
  } catch (e) {
    debugPrint('single_instance: forward failed: $e');
  }
  if (forwarded) exitApp(0);

  InstanceLock? lock;
  try {
    lock = await acquireInstanceLockOrForward(ep, args,
        forwardRetry: forwardRetry);
  } catch (e) {
    debugPrint('single_instance: cannot take the instance lock: $e');
    return null;
  }
  if (lock == null) exitApp(0); // another instance got the request
  return (endpoint: ep, lock: lock);
}

/// The running CLI endpoint: listener + lock + files. [stop] is the window
/// close cleanup; after a crash the leftovers are harmless (the next owner
/// takes the lock and replaces the stale socket).
class CliEndpointOwner {
  CliEndpointOwner._(this._ep, this._listener, this._lock);
  final CliEndpoint _ep;
  final CliListener _listener;
  final InstanceLock _lock;
  bool _stopped = false;

  /// Best effort and idempotent. Files are removed synchronously (before the
  /// first await) so a closing process gets them done even if it exits right
  /// after. The lock is released last, after the listener has stopped (and,
  /// on macOS/Linux, unlinked its socket; on Windows closed every pipe
  /// instance): a relaunch that took the lock earlier could have its fresh
  /// socket unlinked, or fail its FIRST pipe instance with CliEndpointInUse.
  /// The OS drops the lock at exit anyway.
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
    try {
      await _listener.stop();
    } catch (e) {
      debugPrint('single_instance: stop failed: $e');
    } finally {
      _lock.release();
    }
  }
}

/// Starts the CLI endpoint for the instance holding [lock] (taken in main()
/// by [claimSingleInstance]); runs after the first frame.
///
/// Order: token ([CliServer.token]), then bind the socket (a stale socket
/// file is replaced) or create the named pipe, then app.path (best effort;
/// the Windows and Linux CLIs start the app from it). Throws when the
/// endpoint cannot be set up; the lock stays with the caller, so the app
/// stays the single instance and runs without the CLI.
Future<CliEndpointOwner> startCliEndpoint(
  CliEndpoint ep,
  CliServer server, {
  required InstanceLock lock,
  @visibleForTesting
  CliListener Function(CliEndpoint ep, CliServer server) listenerFactory =
      createCliListener,
}) async {
  final listener = listenerFactory(ep, server);
  try {
    await listener.prepare();
    await writeToken(ep.runDir, token: server.token);
    await listener.start();
  } catch (_) {
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
