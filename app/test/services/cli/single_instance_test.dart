import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/single_instance.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server_test.dart' show FakeHandlers;

Future<void> makeStaleSocket(String path) async {
  // Dart unlinks on close; a SIGKILLed app leaves the file. python's
  // bind-and-exit does the same.
  final r = await Process.run('python3', [
    '-c',
    'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])',
    path
  ]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  expect(FileSystemEntity.typeSync(path), FileSystemEntityType.unixDomainSock);
}

void main() {
  final skip = Platform.isWindows ? 'unix sockets only' : null;
  late Directory tmp;
  late CliEndpoint ep;
  final owners = <CliEndpointOwner>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ys');
    ep = CliEndpoint.resolve(
        os: 'linux', env: {'XDG_RUNTIME_DIR': tmp.path}, home: tmp.path);
  });

  tearDown(() async {
    for (final o in owners) {
      await o.stop();
    }
    owners.clear();
    tmp.deleteSync(recursive: true);
  });

  Host prod() => Host(label: 'prod', host: 'p.com', username: 'root');

  Future<CliEndpointOwner> startOwner(FakeHandlers h) async {
    final o = await startCliEndpoint(ep, h, const []);
    owners.add(o!);
    return o;
  }

  test('forwards a yourssh:// URL as open to a running instance', skip: skip,
      () async {
    final h = FakeHandlers([prod()]);
    await startOwner(h);

    expect(
        await forwardToRunningInstance(['yourssh://connect/prod'], ep), isTrue);
    expect(h.calls, ['connect:prod:url']);
  });

  test('a bare second launch forwards activate (focus), not version',
      skip: skip, () async {
    final h = FakeHandlers([]);
    await startOwner(h);

    expect(await forwardToRunningInstance(const [], ep), isTrue);
    expect(h.calls, ['focus']);
  });

  test('an error reply (unknown host) still counts as forwarded', skip: skip,
      () async {
    final h = FakeHandlers([prod()]);
    await startOwner(h);

    expect(
        await forwardToRunningInstance(['yourssh://connect/nope'], ep), isTrue);
    expect(h.calls, isEmpty);
  });

  test('returns false quickly when nothing is listening', skip: skip,
      () async {
    final sw = Stopwatch()..start();
    expect(await forwardToRunningInstance(const [], ep), isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('a stale socket from a crashed run does not look alive', skip: skip,
      () async {
    Directory(ep.runDir).createSync(recursive: true);
    await makeStaleSocket(ep.address);
    await writeToken(ep.runDir);
    expect(await forwardToRunningInstance(const [], ep), isFalse);
  });

  test(
      'lock busy: the request is forwarded, no second listener starts, and '
      'the owner answering an error does not make the loser start one',
      skip: skip, () async {
    final h1 = FakeHandlers([prod()]);
    await startOwner(h1);
    final tokenBefore = File(ep.tokenPath).readAsStringSync();
    final pathFile = File('${ep.runDir}/app.path');
    final appPathBefore = pathFile.readAsStringSync();
    final sockInode = FileStat.statSync(ep.address).changed;

    final h2 = FakeHandlers([prod()]);
    final second = await startCliEndpoint(
        ep, h2, ['yourssh://connect/nope'],
        forwardRetry: const Duration(seconds: 2));

    expect(second, isNull);
    expect(h2.calls, isEmpty); // nothing started on the loser
    expect(File(ep.tokenPath).readAsStringSync(), tokenBefore);
    expect(pathFile.readAsStringSync(), appPathBefore);
    expect(FileStat.statSync(ep.address).changed, sockInode);

    // The owner still serves, with the untouched token.
    expect(await forwardToRunningInstance(['yourssh://connect/prod'], ep),
        isTrue);
    expect(h1.calls, ['connect:prod:url']);
  });

  test('two simultaneous launches on a STALE socket: one owner, token matches',
      skip: skip, () async {
    Directory(ep.runDir).createSync(recursive: true);
    await makeStaleSocket(ep.address);
    await writeToken(ep.runDir); // a previous run's token

    final h1 = FakeHandlers([prod()]);
    final h2 = FakeHandlers([prod()]);
    final results = await Future.wait([
      startCliEndpoint(ep, h1, const [],
          forwardRetry: const Duration(seconds: 3)),
      startCliEndpoint(ep, h2, const [],
          forwardRetry: const Duration(seconds: 3)),
    ]);
    owners.addAll(results.whereType<CliEndpointOwner>());

    expect(results.whereType<CliEndpointOwner>().length, 1);
    expect(results.where((r) => r == null).length, 1);
    final winner = results[0] != null ? h1 : h2;
    final loser = results[0] != null ? h2 : h1;
    // The loser's bare launch forwarded activate to the single owner.
    expect(winner.calls, ['focus']);
    expect(loser.calls, isEmpty);
    // A forward only succeeds when the token file matches the owner's token
    // (a denied reply is retried until the deadline, then false).
    expect(await forwardToRunningInstance(const [], ep), isTrue);
    expect(winner.calls, ['focus', 'focus']);
  });

  test('cleanup removes socket and token and releases the lock', skip: skip,
      () async {
    final h = FakeHandlers([]);
    final o = await startCliEndpoint(ep, h, const []);
    expect(File(ep.tokenPath).existsSync(), isTrue);
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.unixDomainSock);

    await o!.stop();
    await o.stop(); // idempotent

    expect(File(ep.tokenPath).existsSync(), isFalse);
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.notFound);
    // The lock is free again: a new launch becomes the owner.
    final again = await startCliEndpoint(ep, FakeHandlers([]), const []);
    expect(again, isNotNull);
    owners.add(again!);
  });

  test('a lock held by ANOTHER PROCESS is respected', skip: skip, () async {
    Directory(ep.runDir).createSync(recursive: true);
    final holder = await Process.start('python3', [
      '-c',
      'import fcntl,sys,time\n'
          'f=open(sys.argv[1],"w")\n'
          'fcntl.lockf(f, fcntl.LOCK_EX)\n'
          'print("held",flush=True)\n'
          'time.sleep(60)',
      '${ep.runDir}/cli.lock'
    ]);
    addTearDown(holder.kill);
    await holder.stdout.transform(utf8.decoder).firstWhere((s) => s.contains('held'));

    final h = FakeHandlers([]);
    final r = await startCliEndpoint(ep, h, const [],
        forwardRetry: const Duration(milliseconds: 300));

    expect(r, isNull);
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.notFound);
    expect(File(ep.tokenPath).existsSync(), isFalse);
  });

  test('lock-busy error codes per platform', () {
    // Windows LockFileEx: ERROR_LOCK_VIOLATION.
    expect(isLockBusyError(33, windows: true), isTrue);
    expect(isLockBusyError(11, windows: true), isFalse);
    expect(isLockBusyError(13, windows: true), isFalse);
    // POSIX fcntl: EACCES / EAGAIN (Linux 11, macOS 35).
    for (final c in [11, 13, 35]) {
      expect(isLockBusyError(c, windows: false), isTrue, reason: '$c');
    }
    expect(isLockBusyError(33, windows: false), isFalse);
    expect(isLockBusyError(null, windows: false), isFalse);
    expect(isLockBusyError(null, windows: true), isFalse);
  });

  test('every desktop OS resolves an endpoint (Windows: per-SID pipe)', () {
    final ep = resolveCliEndpoint();
    if (Platform.isWindows) {
      expect(ep.address, startsWith(r'\\.\pipe\yourssh-cli-S-1-'));
      expect(ep.runDir, endsWith(r'\YourSSH\run'));
    } else {
      expect(ep.address, endsWith('/cli.sock'));
    }
  });

  group('Windows', skip: Platform.isWindows ? null : 'Windows only', () {
    late Directory wtmp;
    late CliEndpoint wep;
    final wowners = <CliEndpointOwner>[];

    setUp(() {
      wtmp = Directory.systemTemp.createTempSync('ys');
      // Unique pipe name: never a running YourSSH's endpoint.
      wep = CliEndpoint.resolve(
        os: 'windows',
        env: {'LOCALAPPDATA': wtmp.path},
        home: wtmp.path,
        userSid: 'test-$pid-${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      for (final o in wowners) {
        await o.stop();
      }
      wowners.clear();
      wtmp.deleteSync(recursive: true);
    });

    test('owner writes token and app.path; a URL launch is forwarded',
        () async {
      final h = FakeHandlers([prod()]);
      final o = await startCliEndpoint(wep, h, const []);
      wowners.add(o!);
      expect(File(wep.tokenPath).existsSync(), isTrue);
      expect(File('${wep.runDir}/app.path').readAsStringSync(),
          Platform.resolvedExecutable);

      expect(await forwardToRunningInstance(['yourssh://connect/prod'], wep),
          isTrue);
      expect(h.calls, ['connect:prod:url']);

      // Lock busy in-process: the loser forwards activate and starts nothing.
      final h2 = FakeHandlers([prod()]);
      expect(await startCliEndpoint(wep, h2, const []), isNull);
      expect(h2.calls, isEmpty);
      expect(h.calls, ['connect:prod:url', 'focus']);
    });

    test('nothing listening: forward returns false quickly', () async {
      final sw = Stopwatch()..start();
      expect(await forwardToRunningInstance(const [], wep), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('cleanup removes the token, frees the pipe and the lock', () async {
      final o = await startCliEndpoint(wep, FakeHandlers([]), const []);
      await o!.stop();
      await o.stop();
      expect(File(wep.tokenPath).existsSync(), isFalse);
      expect(await forwardToRunningInstance(const [], wep), isFalse);
      final again = await startCliEndpoint(wep, FakeHandlers([]), const []);
      expect(again, isNotNull);
      wowners.add(again!);
    });

    test('a cli.lock held by ANOTHER PROCESS is respected', () async {
      Directory(wep.runDir).createSync(recursive: true);
      final lockPath = '${wep.runDir}\\cli.lock';
      final holder = await Process.start('powershell', [
        '-NoProfile',
        '-Command',
        "\$f = [System.IO.File]::Open('$lockPath', 'OpenOrCreate', "
            "'ReadWrite', 'ReadWrite'); \$f.Lock(0, 1); "
            "Write-Output held; Start-Sleep -Seconds 60",
      ]);
      // Runs before the group tearDown deletes the dir: the file must be
      // closed by then.
      addTearDown(() async {
        holder.kill();
        await holder.exitCode;
      });
      await holder.stdout
          .transform(utf8.decoder)
          .firstWhere((s) => s.contains('held'));

      final r = await startCliEndpoint(wep, FakeHandlers([]), const [],
          forwardRetry: const Duration(milliseconds: 300));
      expect(r, isNull);
      expect(File(wep.tokenPath).existsSync(), isFalse);
      expect(await WindowsPipeTransport().probe(wep), isFalse);
    });
  });
}
