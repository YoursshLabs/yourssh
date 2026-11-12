import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'endpoint.dart';
import 'output.dart';
import 'protocol.dart';
import 'uid.dart';

const String kCliVersion = '0.1.0';

/// The endpoint is missing or refused the connection.
class CliUnreachable implements Exception {
  CliUnreachable(this.message);
  final String message;
  @override
  String toString() => 'CliUnreachable: $message';
}

/// The socket was reached but the connection broke mid-request. The request
/// may have been delivered, so it is never resent.
class CliConnectionLost implements Exception {}

/// The endpoint refused us: EACCES on the socket, ERROR_ACCESS_DENIED on the
/// pipe, or (Windows) the pipe's server runs as another user.
class CliPermissionDenied implements Exception {
  CliPermissionDenied(
      [this.message = 'permission denied on the YourSSH socket']);
  final String message;
  @override
  String toString() => 'CliPermissionDenied: $message';
}

/// Exit-4 message when the pipe's server process is not ours (R22).
const String kPipeOwnedByAnotherUser =
    'the YourSSH pipe is owned by another user';

/// No complete response within the transport timeout.
class CliTimeout implements Exception {
  CliTimeout(this.seconds);
  final int seconds;
}

class _TokenUnreadable implements Exception {
  _TokenUnreadable(this.path, this.reason);
  final String path;
  final String reason;
}

class _Starting implements Exception {}

abstract class CliTransport {
  /// True when something accepts connections on the endpoint.
  Future<bool> probe(CliEndpoint ep) async => false;

  /// Sends one request line, returns one response line. Throws
  /// [CliUnreachable] on a refused / missing endpoint.
  Future<String> roundTrip(CliEndpoint ep, String requestLine);
}

abstract class AppLauncher {
  Future<void> launch(CliEndpoint ep);
}

const String kUsage = '''Usage: yourssh <command> [options]

Commands:
  connect <host>   Open a saved host (id or label) in YourSSH. An unsaved
                   user@host[:port] signs in with your SSH agent's keys;
                   a password-only server needs a saved host
  ls               List saved hosts [--json] [--tag T] [--filter Q]
  version          Show CLI and app versions (never starts the app)
  open <url>       Open a yourssh://connect/<host> URL
  help             Show this help

Environment:
  YOURSSH_DEV=1    Talk to a debug build of the app (flutter run)
''';

String _randomId() {
  final rng = Random.secure();
  return List.generate(8, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Runs the CLI and returns the process exit code.
Future<int> runCli(
  List<String> argv, {
  required CliTransport transport,
  required AppLauncher launcher,
  required CliEndpoint endpoint,
  required IOSink out,
  required IOSink err,
  required bool isTty,
  required Map<String, String> env,
  DateTime Function()? now,
  Future<void> Function(Duration)? delay,
  Duration launchWait = const Duration(seconds: 15),
  int? uid,
  PathInspector? inspector,
}) async {
  now ??= DateTime.now;
  delay ??= (d) => Future<void>.delayed(d);

  int usage(String msg) {
    if (msg.isNotEmpty) err.writeln('yourssh: ${sanitize(msg)}');
    err.write(kUsage);
    return CliExit.usage.code;
  }

  if (argv.isEmpty) return usage('');
  final cmd = argv.first;
  final rest = argv.sublist(1);
  if (cmd == 'help' || cmd == '--help' || cmd == '-h') {
    out.write(kUsage);
    return 0;
  }

  var json = false;
  var requestCmd = cmd;
  final args = <String, Object?>{};
  switch (cmd) {
    case 'connect':
      if (rest.length != 1 || rest.first.startsWith('-')) {
        return usage('connect needs exactly one host');
      }
      args['host'] = rest.first;
    case 'open':
      if (rest.length != 1 || !rest.first.toLowerCase().startsWith('yourssh://')) {
        return usage('open needs a yourssh:// URL');
      }
      args['url'] = rest.first;
    case 'version':
      if (rest.isNotEmpty) return usage('version takes no arguments');
    case 'ls':
      for (var i = 0; i < rest.length; i++) {
        final a = rest[i];
        if (a == '--json') {
          json = true;
        } else if (a == '--tag' || a == '--filter') {
          if (i + 1 >= rest.length) return usage('$a needs a value');
          args[a.substring(2)] = rest[++i];
        } else if (a.startsWith('--tag=')) {
          args['tag'] = a.substring(6);
        } else if (a.startsWith('--filter=')) {
          args['filter'] = a.substring(9);
        } else {
          return usage('ls: unknown argument: $a');
        }
      }
    default:
      return usage('unknown command: $cmd');
  }

  final id = _randomId();

  Future<CliResponse> attempt() async {
    if (endpoint.inSharedTemp) {
      // A temp location another user could have prepared: trust it (and
      // read the token in it) only when it is ours and private.
      await checkSharedRunDir(endpoint,
          uid: uid ?? currentUid(), inspector: inspector ?? SystemPathInspector());
    }
    String? token;
    try {
      token = await readTokenStrict(endpoint.tokenPath);
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      throw _TokenUnreadable(
          endpoint.tokenPath,
          code == 13 || code == 1
              ? 'permission denied'
              : (e.osError?.message ?? e.message));
    }
    if (token == null) {
      // No token: either nobody is running, or the app is still starting.
      if (await transport.probe(endpoint)) throw _Starting();
      throw CliUnreachable('no token');
    }
    final request =
        CliRequest(id: id, token: token, cmd: requestCmd, args: args).encode();
    final line = await transport.roundTrip(endpoint, request);
    return CliResponse.decode(line.trim());
  }

  CliResponse? resp;
  try {
    var launched = false;
    DateTime? deadline;
    while (resp == null) {
      try {
        final r = await attempt();
        if (!r.ok &&
            r.code == CliExit.denied &&
            deadline != null &&
            now().isBefore(deadline)) {
          // The app is up but has not rewritten the token yet.
          await delay(const Duration(milliseconds: 200));
          continue;
        }
        resp = r;
      } on _Starting {
        deadline ??= now().add(launchWait);
        if (!now().isBefore(deadline)) {
          err.writeln('yourssh: YourSSH is starting but did not become ready');
          return CliExit.unreachable.code;
        }
        await delay(const Duration(milliseconds: 200));
      } on CliUnreachable catch (e) {
        if (cmd == 'version') {
          // `version` only reports; it never starts the app.
          out.writeln('yourssh CLI $kCliVersion (protocol $kCliProtocolVersion)');
          out.writeln('YourSSH app: not running');
          return CliExit.unreachable.code;
        }
        if (!launched) {
          launched = true;
          await launcher.launch(endpoint);
          deadline ??= now().add(launchWait);
        } else if (!now().isBefore(deadline!)) {
          err.writeln('yourssh: YourSSH is not running and could not be '
              'started (${sanitize(e.message)})');
          return CliExit.unreachable.code;
        }
        await delay(const Duration(milliseconds: 200));
      }
    }
  } on _TokenUnreadable catch (e) {
    err.writeln('yourssh: cannot read the YourSSH token file '
        '(${sanitize(e.path)}): ${sanitize(e.reason)}');
    return CliExit.denied.code;
  } on CliPermissionDenied catch (e) {
    err.writeln('yourssh: ${sanitize(e.message)}');
    return CliExit.denied.code;
  } on CliConnectionLost {
    err.writeln('yourssh: lost connection to YourSSH');
    return CliExit.runtime.code;
  } on CliTimeout catch (e) {
    err.writeln('yourssh: YourSSH did not respond within ${e.seconds} s');
    return CliExit.runtime.code;
  } on CliUnreachable catch (e) {
    err.writeln('yourssh: YourSSH is not running (${sanitize(e.message)}). '
        'Start YourSSH and retry.');
    return CliExit.unreachable.code;
  } on CliProtocolException catch (e) {
    if (e.code == CliExit.unreachable) {
      err.writeln('yourssh: protocol mismatch, update YourSSH '
          '(and the yourssh CLI) to matching versions');
      return CliExit.unreachable.code;
    }
    err.writeln('yourssh: invalid response from YourSSH');
    return CliExit.runtime.code;
  } on Exception catch (e) {
    err.writeln('yourssh: ${sanitize(e)}');
    return CliExit.runtime.code;
  }

  if (resp.id != id) {
    err.writeln('yourssh: response id mismatch');
    return CliExit.runtime.code;
  }

  if (!resp.ok) {
    final msg = sanitize(resp.error);
    err.writeln('yourssh: ${msg.isEmpty ? 'unknown error' : msg}');
    for (final c in resp.candidates ?? const <Map<String, Object?>>[]) {
      err.writeln('  ${sanitize(c['label'])}  ${hostAddress(c)}');
    }
    return switch (resp.code) {
      CliExit.usage => CliExit.usage.code,
      CliExit.unreachable => CliExit.unreachable.code,
      CliExit.denied => CliExit.denied.code,
      _ => CliExit.runtime.code,
    };
  }

  final result = resp.result;
  final map = result is Map<String, Object?> ? result : const <String, Object?>{};
  switch (cmd) {
    case 'ls':
      final hosts = map['hosts'];
      final list = hosts is List ? hosts : const <Object?>[];
      if (json) {
        out.writeln(jsonHosts(list));
      } else {
        final noColor = (env['NO_COLOR'] ?? '').isNotEmpty;
        out.write(renderHostTable(list, color: isTty && !noColor));
      }
    case 'version':
      out.writeln('yourssh CLI $kCliVersion (protocol $kCliProtocolVersion)');
      out.writeln('YourSSH app ${sanitize(map['app'])} '
          '(protocol ${sanitize(map['protocol'])})');
    default:
      final host = map['host'];
      final label = host is Map<String, Object?> ? sanitize(host['label']) : '';
      out.writeln(label.isEmpty ? 'ok' : 'Opened $label');
  }
  return 0;
}

/// Unix-domain socket transport (macOS / Linux).
class UnixSocketTransport implements CliTransport {
  UnixSocketTransport(
      {this.timeout = const Duration(seconds: 30),
      this.maxResponseBytes = kMaxResponseBytes});
  final Duration timeout;
  final int maxResponseBytes;

  static const _enoent = 2;
  static const _eacces = 13;
  static const _econnrefusedLinux = 111;
  static const _econnrefusedMac = 61;

  Future<Socket> _connect(CliEndpoint ep) async {
    if (Platform.isWindows) {
      throw CliUnreachable('no Unix sockets on Windows (WindowsPipeTransport)');
    }
    try {
      return await Socket.connect(
              InternetAddress(ep.address, type: InternetAddressType.unix), 0)
          .timeout(const Duration(seconds: 2));
    } on SocketException catch (e) {
      switch (e.osError?.errorCode) {
        case _enoent || _econnrefusedLinux || _econnrefusedMac:
          throw CliUnreachable(e.message);
        case _eacces:
          throw CliPermissionDenied();
      }
      rethrow;
    } on TimeoutException {
      throw CliTimeout(2);
    }
  }

  @override
  Future<bool> probe(CliEndpoint ep) async {
    try {
      (await _connect(ep)).destroy();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<String> roundTrip(CliEndpoint ep, String requestLine) async {
    // Connect-phase failures above are the only ones that may be retried.
    final socket = await _connect(ep);
    try {
      try {
        socket.write(requestLine);
        socket.write('\n');
        await socket.flush();
      } on Object {
        throw CliConnectionLost();
      }
      final buf = BytesBuilder(copy: false);
      final done = Completer<void>();
      final sub = socket.listen((chunk) {
        buf.add(chunk);
        if (done.isCompleted) return;
        if (buf.length > maxResponseBytes) {
          done.completeError(
              CliProtocolException(CliExit.usage, 'response too long'));
        } else if (chunk.contains(10)) {
          done.complete();
        }
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }, onError: (Object e) {
        if (!done.isCompleted) done.completeError(CliConnectionLost());
      });
      try {
        await done.future.timeout(timeout);
      } on TimeoutException {
        throw CliTimeout(timeout.inSeconds);
      } finally {
        await sub.cancel();
      }
      final bytes = buf.takeBytes();
      if (bytes.isEmpty) throw CliConnectionLost();
      final text = utf8.decode(bytes, allowMalformed: true);
      final nl = text.indexOf('\n');
      return nl < 0 ? text : text.substring(0, nl);
    } finally {
      socket.destroy();
    }
  }
}

/// What the launcher needs to know about a path (no symlink following).
class PathStat {
  const PathStat(
      {required this.uid,
      required this.mode,
      required this.isRegularFile,
      this.isDirectory = false,
      this.isSocket = false});
  final int uid;

  /// Permission bits (e.g. 0o700 = 448).
  final int mode;
  final bool isRegularFile;
  final bool isDirectory;
  final bool isSocket;
}

/// For a run dir in a shared temp location (the short fallback): the dir
/// must be a real directory owned by [uid] with mode 0700, and the socket,
/// if present, a socket owned by [uid] that nobody else can use. Anything
/// else is [CliPermissionDenied] (exit 4) — checked before the token is read
/// or anything is sent. A missing dir is [CliUnreachable] (app not running).
Future<void> checkSharedRunDir(CliEndpoint ep,
    {required int uid, required PathInspector inspector}) async {
  final dir = await inspector.lstat(ep.runDir);
  if (dir == null) throw CliUnreachable('no run dir');
  if (!dir.isDirectory || dir.uid != uid || (dir.mode & 511) != 448) {
    throw CliPermissionDenied('the YourSSH run dir (${ep.runDir}) is not '
        'private: it must be your own directory with mode 0700');
  }
  final sock = await inspector.lstat(ep.address);
  if (sock != null &&
      (!sock.isSocket || sock.uid != uid || (sock.mode & 63) != 0)) {
    throw CliPermissionDenied('the YourSSH socket (${ep.address}) is not '
        'private: it must be your own socket with no group/other access');
  }
}

/// Test seam for the Linux launch checks.
abstract class PathInspector {
  /// Owner / mode / type of [path] itself (a symlink is not followed), or
  /// null when it does not exist or cannot be inspected.
  Future<PathStat?> lstat(String path);

  /// True when [path] (symlinks followed) is an existing regular file.
  Future<bool> isExistingRegularFile(String path);
}

/// `/usr/bin/stat` (absolute, no PATH lookup; never follows a symlink):
/// BSD `-f '%u %Lp %HT'` on macOS, GNU `-c '%u %a %F'` on Linux. A missing
/// binary or path reads as null.
class SystemPathInspector implements PathInspector {
  @override
  Future<PathStat?> lstat(String path) async {
    try {
      final r = await Process.run(
          '/usr/bin/stat',
          Platform.isMacOS
              ? ['-f', '%u %Lp %HT', path]
              : ['-c', '%u %a %F', path]);
      if (r.exitCode != 0) return null;
      final parts = r.stdout.toString().trim().split(' ');
      if (parts.length < 3) return null;
      final uid = int.tryParse(parts[0]);
      final mode = int.tryParse(parts[1], radix: 8);
      if (uid == null || mode == null) return null;
      final type = parts.sublist(2).join(' ').toLowerCase();
      return PathStat(
          uid: uid,
          mode: mode,
          isRegularFile: type.startsWith('regular'),
          isDirectory: type == 'directory',
          isSocket: type == 'socket');
    } on ProcessException {
      return null;
    }
  }

  @override
  Future<bool> isExistingRegularFile(String path) async =>
      FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
}

/// Linux: execs the path in `<runDir>/app.path`, but only when the run dir and
/// that file belong to us and nobody else can write them.
class LinuxAppLauncher implements AppLauncher {
  LinuxAppLauncher({
    required this.uid,
    PathInspector? inspector,
    Future<void> Function(String path)? spawn,
  })  : inspector = inspector ?? SystemPathInspector(),
        spawn = spawn ?? _spawnDetached;

  final int uid;
  final PathInspector inspector;
  final Future<void> Function(String path) spawn;

  static const _hint = 'start YourSSH once from your launcher';

  static Future<void> _spawnDetached(String path) async {
    await Process.start(path, const [], mode: ProcessStartMode.detached);
  }

  bool _safe(PathStat? s) =>
      s != null && s.uid == uid && (s.mode & 18) == 0; // 0o022

  @override
  Future<void> launch(CliEndpoint ep) async {
    final appPath = '${ep.runDir}/app.path';
    final dir = await inspector.lstat(ep.runDir);
    final file = await inspector.lstat(appPath);
    if (!_safe(dir) || !_safe(file) || !file!.isRegularFile) {
      throw CliUnreachable('$_hint (the app.path file is missing or unsafe)');
    }
    String path;
    try {
      path = (await File(appPath).readAsString()).trim();
    } on FileSystemException {
      path = '';
    }
    if (path.isEmpty ||
        !path.startsWith('/') ||
        !await inspector.isExistingRegularFile(path)) {
      throw CliUnreachable('$_hint (the recorded app path is not usable)');
    }
    try {
      await spawn(path);
    } on ProcessException catch (e) {
      throw CliUnreachable('cannot start YourSSH: ${e.message}');
    }
  }
}

/// Windows: starts the `.exe` recorded in `<runDir>\app.path` (written by
/// the app on start). The run dir is per user under %LOCALAPPDATA%, so there
/// are no owner/mode checks (R24); the recorded path must be an absolute
/// drive path to an existing `.exe` with no control or reserved characters
/// (no UNC/device paths, no `:stream` suffix).
class WindowsAppLauncher implements AppLauncher {
  WindowsAppLauncher({
    PathInspector? inspector,
    Future<String> Function(String path)? read,
    Future<void> Function(String path)? spawn,
  })  : inspector = inspector ?? SystemPathInspector(),
        read = read ?? ((path) => File(path).readAsString()),
        spawn = spawn ?? _spawnDetached;

  final PathInspector inspector;
  final Future<String> Function(String path) read;
  final Future<void> Function(String path) spawn;

  static const _hint = 'start YourSSH once from the Start menu';

  static final _exePath =
      RegExp(r'^[A-Za-z]:\\[^\x00-\x1f\x7f-\x9f"*?<>|:]*\.exe$', caseSensitive: false);

  static Future<void> _spawnDetached(String path) async {
    await Process.start(path, const [], mode: ProcessStartMode.detached);
  }

  @override
  Future<void> launch(CliEndpoint ep) async {
    String path;
    try {
      path = (await read(p.windows.join(ep.runDir, 'app.path'))).trim();
    } on FileSystemException {
      path = '';
    } on FormatException {
      path = '';
    }
    if (!_exePath.hasMatch(path) || !await inspector.isExistingRegularFile(path)) {
      throw CliUnreachable('$_hint (the recorded app path is missing or not usable)');
    }
    try {
      await spawn(path);
    } on ProcessException catch (e) {
      throw CliUnreachable('cannot start YourSSH: ${e.message}');
    }
  }
}

/// macOS: `/usr/bin/open -b com.thangnm.yourssh` (absolute path). A
/// non-zero exit (app not installed, LaunchServices refused) is
/// [CliUnreachable], so the CLI exits 3 at once instead of waiting 15 s.
class MacAppLauncher implements AppLauncher {
  MacAppLauncher(
      {Future<ProcessResult> Function(String exe, List<String> args)? run})
      : run = run ?? ((exe, args) => Process.run(exe, args));

  final Future<ProcessResult> Function(String exe, List<String> args) run;

  static const bundleId = 'com.thangnm.yourssh';

  @override
  Future<void> launch(CliEndpoint ep) async {
    ProcessResult r;
    try {
      r = await run('/usr/bin/open', ['-b', bundleId]);
    } on ProcessException catch (e) {
      throw CliUnreachable('cannot run /usr/bin/open: ${e.message}');
    }
    if (r.exitCode != 0) {
      final detail = r.stderr.toString().trim();
      throw CliUnreachable('"open -b $bundleId" failed (exit ${r.exitCode}'
          '${detail.isEmpty ? '' : ': $detail'}). Install YourSSH in '
          '/Applications or start it once');
    }
  }
}

/// `YOURSSH_DEV=1`: the target is a debug build started with `flutter run`;
/// the installed app must not be launched in its place.
class DevBuildLauncher implements AppLauncher {
  @override
  Future<void> launch(CliEndpoint ep) async => throw CliUnreachable(
      'YOURSSH_DEV=1 targets a debug build; start it with flutter run');
}

/// Starts the app: [MacAppLauncher] on macOS, [LinuxAppLauncher] on Linux,
/// [WindowsAppLauncher] on Windows.
class SystemAppLauncher implements AppLauncher {
  @override
  Future<void> launch(CliEndpoint ep) async {
    if (Platform.isWindows) {
      await WindowsAppLauncher().launch(ep);
      return;
    }
    if (Platform.isMacOS) {
      await MacAppLauncher().launch(ep);
      return;
    }
    await LinuxAppLauncher(uid: currentUid()).launch(ep);
  }
}
