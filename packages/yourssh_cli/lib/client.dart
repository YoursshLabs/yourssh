import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'endpoint.dart';
import 'output.dart';
import 'protocol.dart';

const String kCliVersion = '0.1.0';

/// The endpoint is missing or refused the connection.
class CliUnreachable implements Exception {
  CliUnreachable(this.message);
  final String message;
  @override
  String toString() => 'CliUnreachable: $message';
}

abstract class CliTransport {
  /// Sends one request line, returns one response line. Throws
  /// [CliUnreachable] on a refused / missing endpoint.
  Future<String> roundTrip(CliEndpoint ep, String requestLine);
}

abstract class AppLauncher {
  Future<void> launch(CliEndpoint ep);
}

const String kUsage = '''Usage: yourssh <command> [options]

Commands:
  connect <host>   Open a saved host (or user@host[:port]) in YourSSH
  ls               List saved hosts [--json] [--tag T] [--filter Q]
  version          Show CLI and app versions
  open <url>       Open a yourssh://connect/<host> URL
  help             Show this help
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

  String request;
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
    final token = await readToken(endpoint.tokenPath);
    if (token == null) throw CliUnreachable('no token');
    request = CliRequest(id: id, token: token, cmd: requestCmd, args: args)
        .encode();
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
        if (!r.ok && r.code == CliExit.denied && launched && now().isBefore(deadline!)) {
          // The app is up but has not rewritten the token yet.
          await delay(const Duration(milliseconds: 200));
          continue;
        }
        resp = r;
      } on CliUnreachable catch (e) {
        if (!launched) {
          launched = true;
          await launcher.launch(endpoint);
          deadline = now().add(launchWait);
        } else if (!now().isBefore(deadline!)) {
          err.writeln('yourssh: YourSSH is not running and could not be '
              'started (${sanitize(e.message)})');
          return CliExit.unreachable.code;
        }
        await delay(const Duration(milliseconds: 200));
      }
    }
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
    err.writeln('yourssh: ${sanitize(resp.error)}');
    for (final c in resp.candidates ?? const <Map<String, Object?>>[]) {
      err.writeln('  ${sanitize(c['label'])}  ${hostAddress(c)}');
    }
    return switch (resp.code) {
      CliExit.usage => CliExit.usage.code,
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
  UnixSocketTransport({this.timeout = const Duration(seconds: 30)});
  final Duration timeout;

  @override
  Future<String> roundTrip(CliEndpoint ep, String requestLine) async {
    if (Platform.isWindows) {
      throw CliUnreachable('Windows support arrives in a later build');
    }
    Socket socket;
    try {
      socket = await Socket.connect(
              InternetAddress(ep.address, type: InternetAddressType.unix), 0)
          .timeout(const Duration(seconds: 2));
    } on SocketException catch (e) {
      throw CliUnreachable(e.message);
    } on TimeoutException {
      throw CliUnreachable('connect timed out');
    }
    try {
      socket.write(requestLine);
      socket.write('\n');
      await socket.flush();
      final buf = BytesBuilder(copy: false);
      final done = Completer<void>();
      final sub = socket.listen((chunk) {
        buf.add(chunk);
        if (buf.length > kMaxResponseBytes && !done.isCompleted) {
          done.completeError(
              CliProtocolException(CliExit.usage, 'response too long'));
        } else if (chunk.contains(10) && !done.isCompleted) {
          done.complete();
        }
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }, onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      });
      try {
        await done.future.timeout(timeout);
      } finally {
        await sub.cancel();
      }
      final text = utf8.decode(buf.takeBytes(), allowMalformed: true);
      final nl = text.indexOf('\n');
      return nl < 0 ? text : text.substring(0, nl);
    } on SocketException catch (e) {
      throw CliUnreachable(e.message);
    } finally {
      socket.destroy();
    }
  }
}

/// Starts the app: `open -b` on macOS, the path in `app.path` on Linux.
class SystemAppLauncher implements AppLauncher {
  @override
  Future<void> launch(CliEndpoint ep) async {
    if (Platform.isWindows) {
      throw CliUnreachable('Windows support arrives in a later build');
    }
    if (Platform.isMacOS) {
      await Process.run('open', ['-b', 'com.thangnm.yourssh']);
      return;
    }
    String path;
    try {
      path = (await File('${ep.runDir}/app.path').readAsString()).trim();
    } on FileSystemException {
      path = '';
    }
    if (path.isEmpty) {
      throw CliUnreachable('start YourSSH first (app path unknown)');
    }
    try {
      await Process.start(path, const [], mode: ProcessStartMode.detached);
    } on ProcessException catch (e) {
      throw CliUnreachable('cannot start YourSSH: ${e.message}');
    }
  }
}
