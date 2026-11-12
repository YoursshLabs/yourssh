import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/cli/cli_listener.dart';
import 'package:yourssh/services/cli/single_instance.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server_test.dart' show FakeHandlers;

void main() {
  final skip = Platform.isWindows ? 'unix sockets only' : null;
  late Directory tmp;
  late CliEndpoint ep;
  final listeners = <CliListener>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ys');
    ep = CliEndpoint.resolve(
        os: 'linux', env: {'XDG_RUNTIME_DIR': tmp.path}, home: tmp.path);
  });

  tearDown(() async {
    for (final l in listeners) {
      await l.stop();
    }
    listeners.clear();
    tmp.deleteSync(recursive: true);
  });

  Host prod() => Host(label: 'prod', host: 'p.com', username: 'root');

  test('forwards a yourssh:// URL as open to a running instance', skip: skip,
      () async {
    final h = FakeHandlers([prod()]);
    final r = await startCliEndpoint(ep, h, const []);
    listeners.add(r!);

    expect(
        await forwardToRunningInstance(['yourssh://connect/prod'], ep), isTrue);
    expect(h.calls, ['connect:prod:url']);
  });

  test('a bare second launch forwards activate (focus), not version',
      skip: skip, () async {
    final h = FakeHandlers([]);
    listeners.add((await startCliEndpoint(ep, h, const []))!);

    expect(await forwardToRunningInstance(const [], ep), isTrue);
    expect(h.calls, ['focus']);
  });

  test('returns false quickly when nothing is listening', skip: skip,
      () async {
    final sw = Stopwatch()..start();
    expect(await forwardToRunningInstance(const [], ep), isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('a stale socket from a crashed run does not look alive',
      skip: skip, () async {
    Directory(ep.runDir).createSync(recursive: true);
    // Dart unlinks on close; a SIGKILLed app leaves the file. python's
    // bind-and-exit does the same.
    final r = await Process.run('python3', [
      '-c',
      'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])',
      ep.address
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.unixDomainSock);
    await writeToken(ep.runDir);
    expect(await forwardToRunningInstance(const [], ep), isFalse);
  });

  test('two simultaneous launches: one listener, one forwarded request',
      skip: skip, () async {
    final h1 = FakeHandlers([prod()]);
    final h2 = FakeHandlers([prod()]);
    final args = ['yourssh://connect/prod'];
    final results = await Future.wait([
      startCliEndpoint(ep, h1, args),
      startCliEndpoint(ep, h2, args),
    ]);
    listeners.addAll(results.whereType<CliListener>());

    expect(results.whereType<CliListener>().length, 1);
    expect(results.where((r) => r == null).length, 1);
    // Exactly one request reached the single winner.
    expect(h1.calls.length + h2.calls.length, 1);
    expect([...h1.calls, ...h2.calls], ['connect:prod:url']);
  });
}
