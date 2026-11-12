import 'dart:convert';
import 'dart:io';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/cli_handlers.dart';
import 'package:yourssh/services/cli/cli_listener.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh/services/cli/single_instance.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server_test.dart' show FakeHandlers;

CliServer serverFor(CliHandlers h,
        {Future<void>? ready, DateTime Function()? now}) =>
    CliServer(
        handlers: h,
        token: generateToken(),
        ready: ready,
        now: now ?? DateTime.now);

/// Takes the lock (it must be free) and starts the endpoint, like main().
Future<CliEndpointOwner> startFresh(CliEndpoint ep, CliHandlers h,
    {Future<void>? ready, DateTime Function()? now}) async {
  final lock = await acquireInstanceLockOrForward(ep, const []);
  expect(lock, isNotNull, reason: 'the lock should be free');
  return startCliEndpoint(ep, serverFor(h, ready: ready, now: now),
      lock: lock!);
}

/// The test seam for main()'s exit(): records the code and stops the caller.
class _Exited implements Exception {
  _Exited(this.code);
  final int code;
}

Never _throwExit(int code) => throw _Exited(code);

/// A listener whose stop() waits for [release] (M9 ordering test).
class _SlowStopListener implements CliListener {
  final release = Completer<void>();
  bool stopping = false;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {
    stopping = true;
    await release.future;
  }
}

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

  Future<CliEndpointOwner> startOwner(FakeHandlers h,
      {Future<void>? ready, DateTime Function()? now}) async {
    final o = await startFresh(ep, h, ready: ready, now: now);
    owners.add(o);
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

    final second = await acquireInstanceLockOrForward(
        ep, ['yourssh://connect/nope'],
        forwardRetry: const Duration(seconds: 2));

    expect(second, isNull);
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
    // Each launch: lock (or forward and give up), then the endpoint.
    Future<CliEndpointOwner?> launch(FakeHandlers h) async {
      final lock = await acquireInstanceLockOrForward(ep, const [],
          forwardRetry: const Duration(seconds: 3));
      if (lock == null) return null;
      return startCliEndpoint(ep, serverFor(h), lock: lock);
    }

    final results = await Future.wait([launch(h1), launch(h2)]);
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
    final o = await startFresh(ep, FakeHandlers([]));
    expect(File(ep.tokenPath).existsSync(), isTrue);
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.unixDomainSock);

    await o.stop();
    await o.stop(); // idempotent

    expect(File(ep.tokenPath).existsSync(), isFalse);
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.notFound);
    // The lock is free again: a new launch becomes the owner.
    owners.add(await startFresh(ep, FakeHandlers([])));
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

    final r = await acquireInstanceLockOrForward(ep, const [],
        forwardRetry: const Duration(milliseconds: 300));

    expect(r, isNull);
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.notFound);
    expect(File(ep.tokenPath).existsSync(), isFalse);
  });

  group('I1: the lock is taken in main() before any start-up work', () {
    test('a free lock is taken; the run dir is created 0700; nothing else',
        skip: skip, () async {
      final lock = await acquireInstanceLockOrForward(ep, const []);
      expect(lock, isNotNull);
      addTearDown(lock!.release);
      expect(FileStat.statSync(ep.runDir).mode & 0x1ff, 0x1c0);
      // Token, socket and app.path wait for the first frame.
      expect(File(ep.tokenPath).existsSync(), isFalse);
      expect(FileSystemEntity.typeSync(ep.address),
          FileSystemEntityType.notFound);
      expect(File('${ep.runDir}/app.path').existsSync(), isFalse);
      // Held: a second claim in this process is busy.
      expect(
          await acquireInstanceLockOrForward(ep, const [],
              forwardRetry: const Duration(milliseconds: 100)),
          isNull);
    });

    test('claimSingleInstance: no other instance → returns the held lock',
        skip: skip, () async {
      final claim = await claimSingleInstance(const [],
          resolve: () => ep, exitApp: _throwExit);
      expect(claim, isNotNull);
      addTearDown(claim!.lock.release);
      expect(claim.endpoint.runDir, ep.runDir);
    });

    test(
        'claimSingleInstance: a running owner gets the URL and the launch '
        'exits(0) before returning', skip: skip, () async {
      final h = FakeHandlers([prod()]);
      await startOwner(h);
      await expectLater(
          claimSingleInstance(['yourssh://connect/prod'],
              resolve: () => ep, exitApp: _throwExit),
          throwsA(isA<_Exited>().having((e) => e.code, 'code', 0)));
      expect(h.calls, ['connect:prod:url']);
    });

    test(
        'claimSingleInstance: lock busy while the owner is still starting → '
        'the request is forwarded once it is up, then exit(0)', skip: skip,
        () async {
      // The owner holds the lock but has no endpoint yet (first frame
      // pending): the early forward finds nothing, the lock is busy.
      final lock = await acquireInstanceLockOrForward(ep, const []);
      final h = FakeHandlers([prod()]);
      final claim = claimSingleInstance(['yourssh://connect/prod'],
          resolve: () => ep,
          exitApp: _throwExit,
          forwardRetry: const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      owners.add(await startCliEndpoint(ep, serverFor(h), lock: lock!));
      await expectLater(claim,
          throwsA(isA<_Exited>().having((e) => e.code, 'code', 0)));
      expect(h.calls, ['connect:prod:url']);
    });

    test('claimSingleInstance: an endpoint that cannot be resolved → null, '
        'the app starts without the CLI', () async {
      expect(
          await claimSingleInstance(const [],
              resolve: () => throw StateError('no SID'), exitApp: _throwExit),
          isNull);
    });
  });

  test('M9: the lock is released only after the listener has stopped',
      skip: skip, () async {
    final lock = await acquireInstanceLockOrForward(ep, const []);
    final slow = _SlowStopListener();
    final o = await startCliEndpoint(ep, serverFor(FakeHandlers([])),
        lock: lock!, listenerFactory: (_, _) => slow);
    final stopping = o.stop();
    await pumpEventQueue();
    expect(slow.stopping, isTrue);
    // Still held while the listener may still unlink its socket.
    expect(
        await acquireInstanceLockOrForward(ep, const [],
            forwardRetry: const Duration(milliseconds: 100)),
        isNull);
    slow.release.complete();
    await stopping;
    final again = await acquireInstanceLockOrForward(ep, const []);
    expect(again, isNotNull);
    again!.release();
  });

  group('I3: socket requests share the ready gate and the URL debounce', () {
    test('a socket request before the providers are ready waits', skip: skip,
        () async {
      final gate = Completer<void>();
      final h = FakeHandlers([prod()]);
      await startOwner(h, ready: gate.future);
      final fwd = forwardToRunningInstance(['yourssh://connect/prod'], ep);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.calls, isEmpty);
      gate.complete();
      expect(await fwd, isTrue);
      expect(h.calls, ['connect:prod:url']);
    });

    test('a repeated forwarded open within 2 s is dropped', skip: skip,
        () async {
      var t = DateTime(2026, 1, 1);
      final h = FakeHandlers([prod()]);
      await startOwner(h, now: () => t);
      expect(await forwardToRunningInstance(['yourssh://connect/prod'], ep),
          isTrue);
      t = t.add(const Duration(seconds: 1));
      expect(await forwardToRunningInstance(['yourssh://connect/prod'], ep),
          isTrue); // answered, but nothing opened
      expect(h.calls, ['connect:prod:url']);
      t = t.add(const Duration(seconds: 2));
      await forwardToRunningInstance(['yourssh://connect/prod'], ep);
      expect(h.calls, ['connect:prod:url', 'connect:prod:url']);
    });
  });

  group('M1: a shared-temp run dir must be private before forwarding', () {
    late CliEndpoint sep;
    setUp(() {
      // macOS-style fallback under our temp dir ($TMPDIR/yourssh-run).
      sep = CliEndpoint.resolve(
          os: 'macos', env: {'TMPDIR': tmp.path}, home: '/${'h' * 120}');
      expect(sep.inSharedTemp, isTrue);
    });

    test('ours and 0700: forwarded', skip: skip, () async {
      final h = FakeHandlers([prod()]);
      owners.add(await startFresh(sep, h));
      expect(await forwardToRunningInstance(const [], sep), isTrue);
      expect(h.calls, ['focus']);
    });

    test('run dir not 0700: not forwarded', skip: skip, () async {
      final h = FakeHandlers([prod()]);
      owners.add(await startFresh(sep, h));
      await Process.run('/bin/chmod', ['750', sep.runDir]);
      expect(await forwardToRunningInstance(const [], sep), isFalse);
      expect(h.calls, isEmpty);
    });

    test('socket peer is another uid: not forwarded', skip: skip, () async {
      final h = FakeHandlers([prod()]);
      owners.add(await startFresh(sep, h));
      expect(
          await forwardToRunningInstance(const [], sep,
              peerUid: (_) => currentUid() + 1),
          isFalse);
      expect(
          await forwardToRunningInstance(const [], sep, peerUid: (_) => null),
          isFalse);
      expect(h.calls, isEmpty);
    });
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
    final ep = resolveCliEndpoint(dev: false);
    if (Platform.isWindows) {
      expect(ep.address, startsWith(r'\\.\pipe\yourssh-cli-S-1-'));
      expect(ep.runDir, endsWith(r'\YourSSH\run'));
    } else {
      expect(ep.address, endsWith('/cli.sock'));
    }
    expect(ep.runDir.toLowerCase(), isNot(contains('yourssh-dev')));
  });

  test('I2: a non-release build (tests, flutter run) uses the dev endpoint',
      () {
    final ep = resolveCliEndpoint();
    expect(ep.runDir.toLowerCase(), contains('yourssh-dev'));
    if (Platform.isWindows) {
      expect(ep.address, startsWith(r'\\.\pipe\yourssh-cli-dev-S-1-'));
      expect(ep.runDir, endsWith(r'\YourSSH-dev\run'));
    }
    expect(ep.runDir, isNot(resolveCliEndpoint(dev: false).runDir));
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
      final o = await startFresh(wep, h);
      wowners.add(o);
      expect(File(wep.tokenPath).existsSync(), isTrue);
      expect(File('${wep.runDir}/app.path').readAsStringSync(),
          Platform.resolvedExecutable);

      expect(await forwardToRunningInstance(['yourssh://connect/prod'], wep),
          isTrue);
      expect(h.calls, ['connect:prod:url']);

      // Lock busy in-process: the loser forwards activate and starts nothing.
      expect(await acquireInstanceLockOrForward(wep, const []), isNull);
      expect(h.calls, ['connect:prod:url', 'focus']);
    });

    test('nothing listening: forward returns false quickly', () async {
      final sw = Stopwatch()..start();
      expect(await forwardToRunningInstance(const [], wep), isFalse);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('cleanup removes the token, frees the pipe and the lock', () async {
      final o = await startFresh(wep, FakeHandlers([]));
      await o.stop();
      await o.stop();
      expect(File(wep.tokenPath).existsSync(), isFalse);
      expect(await forwardToRunningInstance(const [], wep), isFalse);
      wowners.add(await startFresh(wep, FakeHandlers([])));
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

      final r = await acquireInstanceLockOrForward(wep, const [],
          forwardRetry: const Duration(milliseconds: 300));
      expect(r, isNull);
      expect(File(wep.tokenPath).existsSync(), isFalse);
      expect(await WindowsPipeTransport().probe(wep), isFalse);
    });
  });
}
