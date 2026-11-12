import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

class FakeTransport implements CliTransport {
  FakeTransport(this.handler);
  String Function(Map<String, Object?> req)? handler;
  final requests = <Map<String, Object?>>[];
  bool up = true;
  bool listening = false; // socket accepts although round trips are not made
  Object? failWith;
  int attempts = 0;

  @override
  Future<bool> probe(CliEndpoint ep) async => up || listening;

  @override
  Future<String> roundTrip(CliEndpoint ep, String line) async {
    attempts++;
    if (!up) throw CliUnreachable('refused');
    if (failWith != null) throw failWith!;
    final req = jsonDecode(line) as Map<String, Object?>;
    requests.add(req);
    return handler!(req);
  }
}

class FakeInspector implements PathInspector {
  FakeInspector(this.stats, this.targetOk);
  final Map<String, PathStat?> stats;
  final bool targetOk;
  @override
  Future<PathStat?> lstat(String path) async => stats[path];
  @override
  Future<bool> isExistingRegularFile(String path) async => targetOk;
}

class FakeLauncher implements AppLauncher {
  FakeLauncher([this.onLaunch]);
  int calls = 0;
  void Function()? onLaunch;
  @override
  Future<void> launch(CliEndpoint ep) async {
    calls++;
    onLaunch?.call();
  }
}

class Sink extends StringBuffer implements IOSink {
  @override
  Encoding encoding = utf8;
  @override
  void add(List<int> data) => write(utf8.decode(data));
  @override
  void addError(Object error, [StackTrace? st]) {}
  @override
  Future addStream(Stream<List<int>> stream) async {}
  @override
  Future close() async {}
  @override
  Future get done async {}
  @override
  Future flush() async {}
  @override
  void writeln([Object? o = '']) => write('$o\n');
}

String ok(Map<String, Object?> req, Object? result) =>
    CliResponse.success(req['id'] as String, result).encode();

void main() {
  unixTransportTests();
  late Directory dir;
  late CliEndpoint ep;
  late Sink out, err;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('yourssh_cli_test');
    ep = CliEndpoint.resolve(
        os: 'linux', env: {'XDG_RUNTIME_DIR': dir.path}, home: dir.path, uid: 1);
    await writeToken(ep.runDir, token: 'tok123');
    out = Sink();
    err = Sink();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<int> run(List<String> argv, FakeTransport t,
      {FakeLauncher? l,
      bool tty = false,
      Map<String, String> env = const {},
      DateTime Function()? now,
      Future<void> Function(Duration)? delay}) {
    return runCli(argv,
        transport: t,
        launcher: l ?? FakeLauncher(),
        endpoint: ep,
        out: out,
        err: err,
        isTty: tty,
        env: env,
        now: now,
        delay: delay);
  }

  test('(b) socket up but token missing: waits without launching', () async {
    await File(ep.tokenPath).delete();
    final t = FakeTransport((r) => ok(r, {'hosts': []}))..listening = true;
    final l = FakeLauncher();
    var clock = DateTime(2026);
    var n = 0;
    final code = await run(['ls'], t,
        l: l,
        now: () => clock,
        delay: (d) async {
          clock = clock.add(d);
          if (++n == 3) {
            await writeToken(ep.runDir, token: 'late');
            t.up = true;
          }
        });
    expect(code, 0);
    expect(l.calls, 0);
    expect(t.requests.single['token'], 'late');
  });

  test('(b) token never appears within 15s: exit 3, never launched', () async {
    await File(ep.tokenPath).delete();
    final t = FakeTransport((r) => ok(r, {}))..listening = true;
    final l = FakeLauncher();
    var clock = DateTime(2026);
    final code = await run(['ls'], t,
        l: l,
        now: () => clock,
        delay: (d) async => clock = clock.add(d));
    expect(code, 3);
    expect(l.calls, 0);
  });

  test('(c) unreadable token: exit 4, no launch', () async {
    if (Platform.isWindows || Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
      return;
    }
    await Process.run('chmod', ['000', ep.tokenPath]);
    final t = FakeTransport((r) => ok(r, {}));
    final l = FakeLauncher();
    expect(await run(['ls'], t, l: l), 4);
    expect(l.calls, 0);
    expect(t.attempts, 0);
    expect(err.toString(), contains('cannot read the YourSSH token file'));
    expect(err.toString(), contains('permission denied'));
  });

  test('mid-request failure sends exactly once and exits 1', () async {
    final t = FakeTransport((r) => ok(r, {}))..failWith = CliConnectionLost();
    final l = FakeLauncher();
    expect(await run(['connect', 'web'], t, l: l), 1);
    expect(t.attempts, 1);
    expect(l.calls, 0);
    expect(err.toString(), contains('lost connection to YourSSH'));
  });

  test('permission denied on socket exits 4', () async {
    final t = FakeTransport((r) => ok(r, {}))..failWith = CliPermissionDenied();
    expect(await run(['ls'], t), 4);
    expect(err.toString(), contains('permission denied on the YourSSH socket'));
  });

  test('response timeout message', () async {
    final t = FakeTransport((r) => ok(r, {}))..failWith = CliTimeout(30);
    expect(await run(['ls'], t), 1);
    expect(err.toString(), contains('YourSSH did not respond within 30 s'));
    expect(err.toString(), isNot(contains('TimeoutException')));
  });

  test('empty server error prints unknown error', () async {
    final t = FakeTransport((r) =>
        CliResponse.failure(r['id'] as String, CliExit.runtime, '').encode());
    expect(await run(['ls'], t), 1);
    expect(err.toString(), contains('unknown error'));
  });

  test('token rotated by the launch is picked up', () async {
    final t = FakeTransport((r) => ok(r, {'hosts': []}))..up = false;
    final l = FakeLauncher(() {
      File(ep.tokenPath).writeAsStringSync('rotated');
      t.up = true;
    });
    expect(await run(['ls'], t, l: l), 0);
    expect(t.requests.single['token'], 'rotated');
  });

  group('LinuxAppLauncher guards', () {
    late Directory d;
    late CliEndpoint lep;
    setUp(() async {
      d = await Directory.systemTemp.createTemp('lg');
      lep = CliEndpoint.resolve(
          os: 'linux', env: {'XDG_RUNTIME_DIR': d.path}, home: d.path, uid: 1);
      await Directory(lep.runDir).create(recursive: true);
      await File('${lep.runDir}/app.path').writeAsString('/opt/ys/app');
    });
    tearDown(() => d.delete(recursive: true));

    final good = <String, PathStat>{
      'RUN': const PathStat(uid: 1000, mode: 448, isRegularFile: false),
      'APP': const PathStat(uid: 1000, mode: 420, isRegularFile: true),
    };

    Future<(Object?, List<String>)> attemptLaunch(
        Map<String, PathStat?> stats, {bool targetOk = true}) async {
      final spawned = <String>[];
      final launcher = LinuxAppLauncher(
        uid: 1000,
        inspector: FakeInspector({
          lep.runDir: stats['RUN'],
          '${lep.runDir}/app.path': stats['APP'],
        }, targetOk),
        spawn: (p) async => spawned.add(p),
      );
      try {
        await launcher.launch(lep);
        return (null, spawned);
      } catch (e) {
        return (e, spawned);
      }
    }

    test('passes with good ownership and modes', () async {
      final (e, spawned) = await attemptLaunch(good);
      expect(e, isNull);
      expect(spawned, ['/opt/ys/app']);
    });

    for (final c in {
      'run dir owned by another uid': {'RUN': const PathStat(uid: 0, mode: 448, isRegularFile: false)},
      'run dir group-writable': {'RUN': const PathStat(uid: 1000, mode: 504, isRegularFile: false)},
      'run dir world-writable': {'RUN': const PathStat(uid: 1000, mode: 447, isRegularFile: false)},
      'run dir missing': {'RUN': null},
      'app.path owned by another uid': {'APP': const PathStat(uid: 0, mode: 420, isRegularFile: true)},
      'app.path group-writable': {'APP': const PathStat(uid: 1000, mode: 436, isRegularFile: true)},
      'app.path world-writable': {'APP': const PathStat(uid: 1000, mode: 422, isRegularFile: true)},
      'app.path not a regular file': {'APP': const PathStat(uid: 1000, mode: 420, isRegularFile: false)},
      'app.path missing': {'APP': null},
    }.entries) {
      test('refuses: ${c.key}', () async {
        final (e, spawned) = await attemptLaunch({...good, ...c.value});
        expect(e, isA<CliUnreachable>());
        expect((e as CliUnreachable).message, contains('start YourSSH once from your launcher'));
        expect(spawned, isEmpty);
      });
    }

    test('refuses relative path content', () async {
      await File('${lep.runDir}/app.path').writeAsString('relative/app');
      final (e, spawned) = await attemptLaunch(good);
      expect(e, isA<CliUnreachable>());
      expect(spawned, isEmpty);
    });

    test('refuses target that is not an existing regular file', () async {
      final (e, spawned) = await attemptLaunch(good, targetOk: false);
      expect(e, isA<CliUnreachable>());
      expect(spawned, isEmpty);
    });
  });

  test('connect sends token and host, exits 0', () async {
    final t = FakeTransport((r) => ok(r, {'host': {'label': 'web'}}));
    expect(await run(['connect', 'web'], t), 0);
    expect(t.requests.single['cmd'], 'connect');
    expect(t.requests.single['args'], {'host': 'web'});
    expect(t.requests.single['token'], 'tok123');
    expect(out.toString(), contains('web'));
  });

  test('ambiguous lists sanitized candidates on stderr, exit 2', () async {
    final t = FakeTransport((r) => CliResponse.failure(
            r['id'] as String, CliExit.usage, 'ambiguous host: w\x1b[2J',
            candidates: [
              {'label': 'web1\x1b[31m', 'username': 'u', 'host': 'h', 'port': 22},
            ]).encode());
    expect(await run(['connect', 'w'], t), 2);
    expect(err.toString(), contains('web1'));
    expect(err.toString(), isNot(contains('\x1b')));
  });

  test('server codes 4 -> 4, other -> 1', () async {
    var t = FakeTransport(
        (r) => CliResponse.failure(r['id'] as String, CliExit.denied, 'denied').encode());
    expect(await run(['ls'], t), 4);
    t = FakeTransport((r) =>
        CliResponse.failure(r['id'] as String, CliExit.runtime, 'internal error').encode());
    expect(await run(['ls'], t), 1);
  });

  test('unreachable: launches once then retries until up, exit 0', () async {
    final t = FakeTransport((r) => ok(r, {'host': {'label': 'web'}}))..up = false;
    final l = FakeLauncher();
    var clock = DateTime(2026);
    var n = 0;
    final code = await run(['connect', 'web'], t,
        l: l,
        now: () => clock,
        delay: (d) async {
          clock = clock.add(d);
          if (++n == 3) t.up = true;
        });
    expect(code, 0);
    expect(l.calls, 1);
  });

  test('never appears within 15s: exit 3, launched once', () async {
    final t = FakeTransport((r) => ok(r, {}))..up = false;
    final l = FakeLauncher();
    var clock = DateTime(2026);
    final code = await run(['ls'], t,
        l: l,
        now: () => clock,
        delay: (d) async => clock = clock.add(d));
    expect(code, 3);
    expect(l.calls, 1);
    expect(err.toString(), contains('YourSSH is not running'));
    expect(clock.difference(DateTime(2026)).inSeconds, inInclusiveRange(15, 16));
  });

  test('launcher unreachable (no app.path) exits 3', () async {
    final t = FakeTransport((r) => ok(r, {}))..up = false;
    final l = FakeLauncher(() => throw CliUnreachable('start YourSSH first'));
    expect(await run(['ls'], t, l: l), 3);
    expect(err.toString(), contains('start YourSSH'));
  });

  test('ls --json prints the hosts array', () async {
    final hosts = [
      {'id': '1', 'label': 'a\x1b', 'host': 'h', 'port': 22, 'tags': <String>[]}
    ];
    final t = FakeTransport((r) => ok(r, {'hosts': hosts}));
    expect(await run(['ls', '--json', '--tag', 'x', '--filter=y'], t), 0);
    expect(jsonDecode(out.toString()), hosts);
    expect(t.requests.single['args'], {'tag': 'x', 'filter': 'y'});
  });

  test('ls table has no ANSI when not a tty or NO_COLOR', () async {
    final result = {
      'hosts': [
        {'label': 'a', 'username': 'u', 'host': 'h', 'port': 22, 'protocol': 'ssh', 'tags': ['t']}
      ]
    };
    var t = FakeTransport((r) => ok(r, result));
    expect(await run(['ls'], t, tty: false), 0);
    expect(out.toString(), isNot(contains('\x1b')));
    expect(out.toString(), contains('u@h:22'));

    out = Sink();
    t = FakeTransport((r) => ok(r, result));
    await run(['ls'], t, tty: true, env: {'NO_COLOR': '1'});
    expect(out.toString(), isNot(contains('\x1b')));

    out = Sink();
    t = FakeTransport((r) => ok(r, result));
    await run(['ls'], t, tty: true);
    expect(out.toString(), contains('\x1b'));
  });

  test('unknown command and no args: usage, exit 2', () async {
    final t = FakeTransport((r) => ok(r, {}));
    expect(await run(['bogus'], t), 2);
    expect(err.toString(), contains('Usage:'));
    expect(await run([], t), 2);
    expect(t.attempts, 0);
  });

  test('help exits 0 and hides activate', () async {
    final t = FakeTransport((r) => ok(r, {}));
    expect(await run(['--help'], t), 0);
    expect(await run(['help'], t), 0);
    expect(out.toString(), isNot(contains('activate')));
    expect(await run(['activate'], t), 2);
  });

  test('version prints CLI and app versions', () async {
    final t = FakeTransport((r) => ok(r, {'app': '1.2.3', 'protocol': 1}));
    expect(await run(['version'], t), 0);
    expect(out.toString(), contains('CLI'));
    expect(out.toString(), contains('1.2.3'));
  });

  test('protocol mismatch: exit 3 update YourSSH', () async {
    final t = FakeTransport((r) => '{"v":99,"id":"x","ok":true,"result":{}}');
    expect(await run(['version'], t), 3);
    expect(err.toString(), contains('update YourSSH'));
  });

  test('response id mismatch exits 1', () async {
    final t = FakeTransport((r) => CliResponse.success('other', {}).encode());
    expect(await run(['ls'], t), 1);
  });

  test('open requires yourssh:// (case-insensitive)', () async {
    final t = FakeTransport((r) => ok(r, {'host': {'label': 'web'}}));
    expect(await run(['open', 'http://x'], t), 2);
    expect(t.attempts, 0);
    expect(await run(['open', 'YourSSH://connect/web'], t), 0);
    expect(t.requests.single['cmd'], 'open');
    expect(t.requests.single['args'], {'url': 'YourSSH://connect/web'});
  });
}

void unixTransportTests() {
  Future<(CliEndpoint, ServerSocket)> serve(
      void Function(Socket) onClient) async {
    final d = await Directory.systemTemp.createTemp('ys');
    addTearDown(() => d.delete(recursive: true));
    final ep = CliEndpoint.resolve(
        os: 'linux', env: {'XDG_RUNTIME_DIR': d.path}, home: d.path, uid: 1);
    await Directory(ep.runDir).create(recursive: true);
    final server = await ServerSocket.bind(
        InternetAddress(ep.address, type: InternetAddressType.unix), 0);
    addTearDown(server.close);
    server.listen(onClient);
    return (ep, server);
  }

  test('oversized response is a protocol error', () async {
    final (ep, _) = await serve((s) {
      s.add(List.filled(5000, 65));
      s.flush();
    });
    await expectLater(
        UnixSocketTransport(maxResponseBytes: 1000).roundTrip(ep, 'x'),
        throwsA(isA<CliProtocolException>()));
  });

  test('no newline before timeout raises CliTimeout', () async {
    final (ep, _) = await serve((s) => s.write('partial'));
    await expectLater(
        UnixSocketTransport(timeout: const Duration(milliseconds: 200))
            .roundTrip(ep, 'x'),
        throwsA(isA<CliTimeout>()));
  });

  test('multibyte UTF-8 split across writes decodes intact', () async {
    final bytes = utf8.encode('h\u00e9llo \u{1F600}\n');
    final (ep, _) = await serve((s) async {
      s.add(bytes.sublist(0, 2)); // splits the e-acute
      await s.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.add(bytes.sublist(2, 9)); // splits the emoji
      await s.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.add(bytes.sublist(9));
      await s.flush();
    });
    expect(await UnixSocketTransport().roundTrip(ep, 'x'), 'h\u00e9llo \u{1F600}');
  });

  test('peer closing before any reply is a lost connection', () async {
    final (ep, _) = await serve((s) => s.destroy());
    await expectLater(UnixSocketTransport().roundTrip(ep, 'x'),
        throwsA(isA<CliConnectionLost>()));
  });

  test('probe: true when listening, false when absent', () async {
    final (ep, _) = await serve((s) => s.destroy());
    expect(await UnixSocketTransport().probe(ep), isTrue);
    final missing = CliEndpoint.resolve(
        os: 'linux', env: {'XDG_RUNTIME_DIR': '/nonexistent-ys'}, home: '/x', uid: 1);
    expect(await UnixSocketTransport().probe(missing), isFalse);
  });

  test('UnixSocketTransport round-trips a line; missing socket is unreachable',
      () async {
    if (Platform.isWindows) return;
    final d = await Directory.systemTemp.createTemp('ys');
    addTearDown(() => d.delete(recursive: true));
    final ep = CliEndpoint.resolve(
        os: 'linux', env: {'XDG_RUNTIME_DIR': d.path}, home: d.path, uid: 1);
    await expectLater(UnixSocketTransport().roundTrip(ep, 'x'),
        throwsA(isA<CliUnreachable>()));
    await Directory(ep.runDir).create(recursive: true);
    final server = await ServerSocket.bind(
        InternetAddress(ep.address, type: InternetAddressType.unix), 0);
    addTearDown(server.close);
    server.listen((s) {
      utf8.decoder.bind(s).listen((data) {
        s.write('echo:${data.trim()}\n');
      });
    });
    expect(await UnixSocketTransport().roundTrip(ep, 'hello'), 'echo:hello');
  });
}
