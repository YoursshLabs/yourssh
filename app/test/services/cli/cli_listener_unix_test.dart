import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/cli/cli_listener.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server_test.dart' show FakeHandlers;

const tok = 'secret-token';

Future<String> roundTrip(String address, String line) async {
  final s = await Socket.connect(
      InternetAddress(address, type: InternetAddressType.unix), 0);
  s.write(line);
  await s.flush();
  final out = await utf8.decoder.bind(s).join();
  s.destroy();
  return out;
}

String versionReq() =>
    CliRequest(id: 'r1', token: tok, cmd: 'version', args: const {}).encode();

String mode(String path) =>
    (FileStat.statSync(path).mode & 0xFFF).toRadixString(8);

void main() {
  late Directory tmp;
  late CliEndpoint ep;
  late CliServer server;
  CliListener? listener;

  setUp(() {
    // Unix socket paths are limited to ~104 bytes; keep the dir short.
    tmp = Directory.systemTemp.createTempSync('ys');
    ep = CliEndpoint.resolve(
      // Linux layout keeps the path short; the macOS one can exceed sun_path
      // inside the long macOS temp dir.
      os: 'linux',
      env: {'XDG_RUNTIME_DIR': tmp.path},
      home: tmp.path,
    );
    server = CliServer(handlers: FakeHandlers([]), token: tok);
  });

  tearDown(() async {
    await listener?.stop();
    listener = null;
    tmp.deleteSync(recursive: true);
  });

  final skip = Platform.isWindows ? 'unix sockets only' : null;

  test('answers a version request; socket 0600, run dir 0700', skip: skip,
      () async {
    listener = createCliListener(ep, server);
    await listener!.start();
    final out = await roundTrip(ep.address, '${versionReq()}\n');
    expect(CliResponse.decode(out.trim()).ok, isTrue);
    expect(out, contains('"app"'));
    expect(mode(ep.address), '600');
    expect(mode(ep.runDir), '700');
  });

  test('replaces a stale socket file left by a dead listener', skip: skip,
      () async {
    Directory(ep.runDir).createSync(recursive: true);
    final dead = await ServerSocket.bind(
        InternetAddress(ep.address, type: InternetAddressType.unix), 0);
    await dead.close(); // leaves the file behind on some platforms
    if (!File(ep.address).existsSync()) {
      // Dart unlinks on close; recreate a stale node via a raw bind.
      final p = await Process.run('python3', [
        '-c',
        'import socket,sys;s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1])',
        ep.address
      ]);
      expect(p.exitCode, 0, reason: '${p.stderr}');
    }
    expect(FileSystemEntity.typeSync(ep.address), isNot(FileSystemEntityType.notFound));
    listener = createCliListener(ep, server);
    await listener!.start();
    final out = await roundTrip(ep.address, '${versionReq()}\n');
    expect(CliResponse.decode(out.trim()).ok, isTrue);
  });

  test('second listener on a live endpoint throws CliEndpointInUse',
      skip: skip, () async {
    listener = createCliListener(ep, server);
    await listener!.start();
    final second = createCliListener(ep, server);
    await expectLater(second.start(), throwsA(isA<CliEndpointInUse>()));
    // The first one still serves.
    final out = await roundTrip(ep.address, '${versionReq()}\n');
    expect(CliResponse.decode(out.trim()).ok, isTrue);
  });

  test('oversized request closes the connection; listener keeps serving',
      skip: skip, () async {
    listener = createCliListener(ep, server);
    await listener!.start();
    final s = await Socket.connect(
        InternetAddress(ep.address, type: InternetAddressType.unix), 0);
    final done = Completer<List<int>>();
    final got = <int>[];
    s.listen(got.addAll,
        onDone: () => done.complete(got),
        onError: (_) {
          if (!done.isCompleted) done.complete(got);
        },
        cancelOnError: true);
    try {
      s.add(List.filled(70 * 1024, 0x61));
      await s.flush();
    } catch (_) {}
    final bytes = await done.future.timeout(const Duration(seconds: 3));
    expect(bytes, isEmpty);
    s.destroy();
    final out = await roundTrip(ep.address, '${versionReq()}\n');
    expect(CliResponse.decode(out.trim()).ok, isTrue);
  });

  test('stop removes the socket file', skip: skip, () async {
    listener = createCliListener(ep, server);
    await listener!.start();
    expect(File(ep.address).existsSync(), isTrue);
    await listener!.stop();
    expect(FileSystemEntity.typeSync(ep.address),
        FileSystemEntityType.notFound);
  });
}
