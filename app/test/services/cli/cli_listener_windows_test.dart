import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/cli/cli_listener.dart';
import 'package:yourssh/services/cli/cli_listener_windows.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh_cli/win_pipe.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_server_test.dart' show FakeHandlers;

const tok = 'secret-token';

String versionReq() =>
    CliRequest(id: 'r1', token: tok, cmd: 'version', args: const {}).encode();

/// Raw client in a worker isolate (the listener dispatches on this one):
/// open, write [data], then read until a newline, close or [timeoutMs].
Future<(List<int>, PipeIoEnd)> rawExchange(String address, List<int> data,
        {int timeoutMs = 5000}) =>
    Isolate.run(() {
      final h = openPipeClient(address);
      try {
        writePipeAll(h, data, timeoutMs: timeoutMs);
        final r =
            readPipeLine(h, timeoutMs: timeoutMs, maxBytes: kMaxResponseBytes);
        return (r.bytes.toList(), r.end);
      } finally {
        closeWinHandle(h);
      }
    });

/// Reads from an already-open client handle until the server drops it.
Future<(List<int>, PipeIoEnd, Duration)> readUntilDropped(int h,
        {int timeoutMs = 10000}) =>
    Isolate.run(() {
      final sw = Stopwatch()..start();
      final r = readPipeLine(h, timeoutMs: timeoutMs, maxBytes: 1 << 20);
      return (r.bytes.toList(), r.end, sw.elapsed);
    });

void main() {
  final skip = Platform.isWindows ? null : 'Windows named pipes only';
  late Directory tmp;
  late CliEndpoint ep;
  late CliServer server;
  final listeners = <CliListener>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ys');
    // A unique pipe name: never the real endpoint of a running YourSSH.
    ep = CliEndpoint.resolve(
      os: 'windows',
      env: {'LOCALAPPDATA': tmp.path},
      home: tmp.path,
      userSid: 'test-$pid-${Random().nextInt(1 << 30)}',
    );
    server = CliServer(handlers: FakeHandlers([]), token: tok);
  });

  tearDown(() async {
    for (final l in listeners) {
      await l.stop();
    }
    listeners.clear();
    tmp.deleteSync(recursive: true);
  });

  Future<WindowsPipeCliListener> startListener(
      {Duration readTimeout = kCliReadTimeout}) async {
    final l = WindowsPipeCliListener(ep, server, readTimeout: readTimeout);
    listeners.add(l);
    await l.start();
    return l;
  }

  test('createCliListener returns the named-pipe listener', skip: skip, () {
    expect(createCliListener(ep, server), isA<WindowsPipeCliListener>());
  });

  test('(a) answers a version request from a raw client', skip: skip,
      () async {
    await startListener();
    final (bytes, end) =
        await rawExchange(ep.address, utf8.encode('${versionReq()}\n'));
    expect(end, PipeIoEnd.newline);
    final resp = CliResponse.decode(utf8.decode(bytes));
    expect(resp.ok, isTrue);
    expect(resp.id, 'r1');
    expect(jsonEncode(resp.result), contains('"app"'));
    expect(Directory(ep.runDir).existsSync(), isTrue);
  });

  test('(b) a second listener throws CliEndpointInUse; the first serves on',
      skip: skip, () async {
    await startListener();
    final second = WindowsPipeCliListener(ep, server);
    await expectLater(second.start(), throwsA(isA<CliEndpointInUse>()));
    await second.stop(); // must not disturb the live instance
    final line = await WindowsPipeTransport().roundTrip(ep, versionReq());
    expect(CliResponse.decode(line).ok, isTrue);
  });

  test('(c) a client that never sends a newline does not block others and '
      'is dropped after the read timeout', skip: skip, () async {
    const readTimeout = Duration(seconds: 2);
    await startListener(readTimeout: readTimeout);

    final slow = openPipeClient(ep.address);
    addTearDown(() => closeWinHandle(slow));
    expect(writePipeAll(slow, utf8.encode('{"v":1,"partial'), timeoutMs: 2000),
        PipeIoEnd.done);
    final dropped = readUntilDropped(slow);

    final sw = Stopwatch()..start();
    final line = await WindowsPipeTransport().roundTrip(ep, versionReq());
    expect(CliResponse.decode(line).ok, isTrue);
    expect(sw.elapsed, lessThan(readTimeout),
        reason: 'the second client was served while the first one hung');

    final (bytes, end, after) = await dropped;
    expect(bytes, isEmpty);
    expect(end, PipeIoEnd.closed);
    expect(after, lessThan(readTimeout + const Duration(seconds: 3)));
  });

  test('(d) an oversized request is dropped without a reply', skip: skip,
      () async {
    await startListener();
    final (bytes, end) =
        await rawExchange(ep.address, List.filled(70 * 1024, 0x61));
    expect(bytes, isEmpty);
    expect(end, isNot(PipeIoEnd.timeout));
    expect(end, isNot(PipeIoEnd.newline));
    // The listener keeps serving.
    final line = await WindowsPipeTransport().roundTrip(ep, versionReq());
    expect(CliResponse.decode(line).ok, isTrue);
  });

  test('a request with a wrong token gets a denied reply', skip: skip,
      () async {
    await startListener();
    final bad = CliRequest(id: 'r2', token: 'nope', cmd: 'version', args: const {})
        .encode();
    final line = await WindowsPipeTransport().roundTrip(ep, bad);
    final resp = CliResponse.decode(line);
    expect(resp.ok, isFalse);
    expect(resp.code, CliExit.denied);
  });

  test('(e) stop() returns promptly with no client and frees the name',
      skip: skip, () async {
    final l = await startListener();
    final sw = Stopwatch()..start();
    await l.stop();
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(await WindowsPipeTransport().probe(ep), isFalse);
    // Every handle is closed: a new FIRST instance can be created.
    await startListener();
    expect(await WindowsPipeTransport().probe(ep), isTrue);
  });

  test('stop() while a client is connected but silent returns promptly',
      skip: skip, () async {
    final l = await startListener();
    final slow = openPipeClient(ep.address);
    addTearDown(() => closeWinHandle(slow));
    final dropped = readUntilDropped(slow);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final sw = Stopwatch()..start();
    await l.stop();
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    final (bytes, end, _) = await dropped;
    expect(bytes, isEmpty);
    expect(end, PipeIoEnd.closed);
  });

  test('(f) WindowsPipeTransport round-trips through the listener',
      skip: skip, () async {
    await startListener();
    for (var i = 0; i < 3; i++) {
      final line = await WindowsPipeTransport().roundTrip(ep, versionReq());
      final resp = CliResponse.decode(line);
      expect(resp.ok, isTrue);
      expect(resp.id, 'r1');
    }
    expect(await WindowsPipeTransport().probe(ep), isTrue);
  });
}
