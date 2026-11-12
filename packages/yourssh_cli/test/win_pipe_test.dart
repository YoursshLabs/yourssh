import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:test/test.dart';
import 'package:yourssh_cli/win_pipe.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

final _windowsOnly = Platform.isWindows ? null : 'Windows named pipes only';

/// A test endpoint whose pipe name cannot clash with a running YourSSH.
CliEndpoint testEndpoint() => CliEndpoint.resolve(
      os: 'windows',
      env: {'LOCALAPPDATA': Directory.systemTemp.path},
      home: Directory.systemTemp.path,
      userSid: 'test-$pid-${Random().nextInt(1 << 30)}',
    );

// Top-level (no captured context), so Isolate.run can send them.
String? echoReply(String line) => 'echo:$line \u00e9\u{1F600}';
String? noReply(String line) => null;
bool rejectPeer(int pipe) => false;

/// Retries [attempt] while the server isolate has not created its pipe yet
/// (CliUnreachable), for up to 3 s. A failed open consumes nothing.
Future<T> whenUp<T>(Future<T> Function() attempt) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (true) {
    try {
      return await attempt();
    } on CliUnreachable {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// Serves exactly one client on [address] in a background isolate: reads a
/// request line (through [peerCheck]) and answers with [reply] (null: close
/// without a reply). Returns the request line it accepted, or null.
Future<String?> serveOnce(String address, String sid,
        {String? Function(String line)? reply,
        int replyBytes = 0,
        bool Function(int pipe) peerCheck = pipeClientIsCurrentUser}) =>
    Isolate.run(() {
      final pipe = createPipeServerInstance(address, sid: sid, first: true);
      final stop = createStopEvent();
      try {
        if (waitForPipeClient(pipe, stopEvent: stop) != PipeConnect.connected) {
          return null;
        }
        final line = serveReadRequest(pipe,
            stopEvent: stop,
            timeoutMs: 5000,
            maxBytes: kMaxRequestBytes,
            peerCheck: peerCheck);
        if (line == null) return null;
        if (replyBytes > 0) {
          serveWriteResponse(pipe, List.filled(replyBytes, 0x61),
              stopEvent: stop, timeoutMs: 5000);
          return line;
        }
        final out = reply?.call(line);
        if (out != null) {
          serveWriteResponse(pipe, utf8.encode('$out\n'),
              stopEvent: stop, timeoutMs: 5000);
        }
        return line;
      } finally {
        closeWinHandle(pipe);
        closeWinHandle(stop);
      }
    });

/// Accepts one client and reports what it sent before closing (bytes, end).
Future<(int, PipeIoEnd)> recordOnce(String address, String sid) =>
    Isolate.run(() {
      final pipe = createPipeServerInstance(address, sid: sid, first: true);
      final stop = createStopEvent();
      try {
        // clientGone: it connected and closed before we listened; whatever
        // it wrote is still readable.
        if (waitForPipeClient(pipe, stopEvent: stop) == PipeConnect.stopped) {
          return (-1, PipeIoEnd.failed);
        }
        final r = readPipeLine(pipe, timeoutMs: 5000, maxBytes: 1 << 20);
        return (r.bytes.length, r.end);
      } finally {
        closeWinHandle(pipe);
        closeWinHandle(stop);
      }
    });

/// The client side of R22 with the server check forced to fail.
Future<String> roundTripRejectingServer(String address, String line) =>
    Isolate.run(() => pipeRoundTrip(address, line,
        timeoutMs: 5000,
        maxResponseBytes: kMaxResponseBytes,
        busyWaitMs: 2000,
        peerCheck: rejectPeer));

void main() {
  group('pipeSddlForSid', () {
    test('grants GENERIC_ALL to the SID only, protected DACL', () {
      expect(pipeSddlForSid('S-1-5-21-111-222-333-1001'),
          'D:P(A;;GA;;;S-1-5-21-111-222-333-1001)');
    });

    for (final bad in [
      '',
      'WD',
      's-1-5-21-1',
      'S-1-5-21-1)(A;;GA;;;WD',
      'S-1-5-21-1;WD',
      'S-1-',
      'S-1-5-21-1 ',
      'S-1-5-21-x',
    ]) {
      test('rejects ${jsonEncode(bad)}', () {
        expect(() => pipeSddlForSid(bad), throwsArgumentError);
      });
    }
  });

  test('pipeExists is false for a name that is not listed', () {
    expect(pipeExists(testEndpoint().address), isFalse);
    expect(pipeExists('not-a-pipe-path'), isFalse);
    expect(pipeExists(r'\\.\pipe\'), isFalse);
  });

  group('Windows', skip: _windowsOnly, () {
    test('(g) currentUserSid is a SID string', () {
      final sid = currentUserSid();
      expect(sid, startsWith('S-1-'));
      expect(sid, matches(RegExp(r'^S-1-\d+(-\d+)+$')));
      expect(currentUserSid(), sid); // stable
    });

    test('our own process runs as the current user', () {
      expect(processRunsAsCurrentUser(pid), isTrue);
      expect(processRunsAsCurrentUser(0), isFalse);
    });

    test('a missing pipe is unreachable; probe is false', () async {
      final ep = testEndpoint();
      await expectLater(WindowsPipeTransport().roundTrip(ep, 'x'),
          throwsA(isA<CliUnreachable>()));
      expect(await WindowsPipeTransport().probe(ep), isFalse);
    });

    test('a second FIRST instance fails; the name is listed until closed',
        () {
      final ep = testEndpoint();
      final sid = currentUserSid();
      final a = createPipeServerInstance(ep.address, sid: sid, first: true);
      var closed = false;
      addTearDown(() {
        if (!closed) closeWinHandle(a);
      });
      expect(
          () => createPipeServerInstance(ep.address, sid: sid, first: true),
          throwsA(isA<WinPipeException>()));
      expect(pipeExists(ep.address), isTrue);
      expect(pipeExists(ep.address.toUpperCase()), isTrue);
      closeWinHandle(a);
      closed = true;
      expect(pipeExists(ep.address), isFalse);
    });

    test('transport round trip (multibyte), then the server is gone',
        () async {
      final ep = testEndpoint();
      final server = serveOnce(ep.address, currentUserSid(), reply: echoReply);
      expect(await whenUp(() => WindowsPipeTransport().roundTrip(ep, 'hello')),
          'echo:hello \u00e9\u{1F600}');
      expect(await server, 'hello');
      expect(await WindowsPipeTransport().probe(ep), isFalse);
    });

    test('server closing without a reply is a lost connection', () async {
      final ep = testEndpoint();
      final server = serveOnce(ep.address, currentUserSid(), reply: noReply);
      await expectLater(
          whenUp(() => WindowsPipeTransport().roundTrip(ep, 'x')),
          throwsA(isA<CliConnectionLost>()));
      await server;
    });

    test('no reply before the timeout raises CliTimeout', () async {
      final ep = testEndpoint();
      final pipe = createPipeServerInstance(ep.address,
          sid: currentUserSid(), first: true);
      addTearDown(() => closeWinHandle(pipe));
      await expectLater(
          WindowsPipeTransport(timeout: const Duration(milliseconds: 500))
              .roundTrip(ep, 'x'),
          throwsA(isA<CliTimeout>()));
    });

    test('oversized response is a protocol error', () async {
      final ep = testEndpoint();
      final server = serveOnce(ep.address, currentUserSid(), replyBytes: 5000);
      await expectLater(
          whenUp(() =>
              WindowsPipeTransport(maxResponseBytes: 1000).roundTrip(ep, 'x')),
          throwsA(isA<CliProtocolException>()));
      await server;
    });

    test('R22 client: a foreign server gets 0 bytes and the CLI exits 4',
        () async {
      final ep = testEndpoint();
      final server = recordOnce(ep.address, currentUserSid());
      await expectLater(
          whenUp(() => roundTripRejectingServer(ep.address, '{"token":"t"}')),
          throwsA(isA<CliPermissionDenied>().having(
              (e) => e.message, 'message', kPipeOwnedByAnotherUser)));
      final (bytes, end) = await server;
      expect(bytes, 0);
      expect(end, PipeIoEnd.closed);
    });

    test('R22 server: a foreign client is closed without a reply', () async {
      final ep = testEndpoint();
      final server = serveOnce(ep.address, currentUserSid(),
          reply: echoReply, peerCheck: rejectPeer);
      await expectLater(
          whenUp(() => WindowsPipeTransport().roundTrip(ep, 'hello')),
          throwsA(isA<CliConnectionLost>()));
      expect(await server, isNull);
    });

    test('probe: a foreign server is CliPermissionDenied', () async {
      final ep = testEndpoint();
      final pipe = createPipeServerInstance(ep.address,
          sid: currentUserSid(), first: true);
      addTearDown(() => closeWinHandle(pipe));
      await expectLater(
          WindowsPipeTransport(peerCheck: rejectPeer).probe(ep),
          throwsA(isA<CliPermissionDenied>().having(
              (e) => e.message, 'message', kPipeOwnedByAnotherUser)));
    });

    test('the server sees its client as the current user', () {
      final ep = testEndpoint();
      final sid = currentUserSid();
      final pipe = createPipeServerInstance(ep.address, sid: sid, first: true);
      addTearDown(() => closeWinHandle(pipe));
      final client = openPipeClient(ep.address);
      addTearDown(() => closeWinHandle(client));
      final stop = createStopEvent();
      addTearDown(() => closeWinHandle(stop));
      expect(waitForPipeClient(pipe, stopEvent: stop), PipeConnect.connected);
      expect(pipeClientIsCurrentUser(pipe), isTrue);
      expect(pipeServerIsCurrentUser(client), isTrue);
    });

    test('a signalled stop event ends waitForPipeClient', () {
      final ep = testEndpoint();
      final pipe = createPipeServerInstance(ep.address,
          sid: currentUserSid(), first: true);
      addTearDown(() => closeWinHandle(pipe));
      final stop = createStopEvent();
      addTearDown(() => closeWinHandle(stop));
      signalEvent(stop);
      expect(waitForPipeClient(pipe, stopEvent: stop), PipeConnect.stopped);
    });

    test('writeToken overwrites the token in place', () async {
      final dir = Directory.systemTemp.createTempSync('ystok');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = await writeToken(dir.path);
      final reader =
          File('${dir.path}\\cli.token').openSync(); // held open meanwhile
      addTearDown(reader.closeSync);
      final b = await writeToken(dir.path);
      expect(b, isNot(a));
      expect(await readToken('${dir.path}\\cli.token'), b);
    });
  });
}
