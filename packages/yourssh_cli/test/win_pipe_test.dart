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

/// Serves exactly one client on [address] in a background isolate: reads a
/// request line and answers with [reply] (null: close without a reply).
Future<void> serveOnce(String address, String sid,
        {String? Function(String line)? reply, int replyBytes = 0}) =>
    Isolate.run(() {
      final pipe = createPipeServerInstance(address, sid: sid, first: true);
      final stop = createStopEvent();
      try {
        if (waitForPipeClient(pipe, stopEvent: stop) != PipeConnect.connected) {
          return;
        }
        final line = serveReadRequest(pipe,
            stopEvent: stop, timeoutMs: 5000, maxBytes: kMaxRequestBytes);
        if (line == null) return;
        if (replyBytes > 0) {
          serveWriteResponse(pipe, List.filled(replyBytes, 0x61),
              stopEvent: stop, timeoutMs: 5000);
          return;
        }
        final out = reply?.call(line);
        if (out == null) return;
        serveWriteResponse(pipe, utf8.encode('$out\n'),
            stopEvent: stop, timeoutMs: 5000);
      } finally {
        closeWinHandle(pipe);
        closeWinHandle(stop);
      }
    });

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

  group('Windows', skip: _windowsOnly, () {
    test('(g) currentUserSid is a SID string', () {
      final sid = currentUserSid();
      expect(sid, startsWith('S-1-'));
      expect(sid, matches(RegExp(r'^S-1-\d+(-\d+)+$')));
      expect(currentUserSid(), sid); // stable
    });

    test('our own process runs as the current user', () {
      expect(processRunsAsCurrentUser(pid), isTrue);
      expect(processRunsAsCurrentUser(0), isFalse); // System Idle Process
    });

    test('a missing pipe is unreachable; probe is false', () async {
      final ep = testEndpoint();
      await expectLater(WindowsPipeTransport().roundTrip(ep, 'x'),
          throwsA(isA<CliUnreachable>()));
      expect(await WindowsPipeTransport().probe(ep), isFalse);
    });

    test('a second FIRST instance of the same name is refused', () {
      final ep = testEndpoint();
      final sid = currentUserSid();
      final a = createPipeServerInstance(ep.address, sid: sid, first: true);
      addTearDown(() => closeWinHandle(a));
      expect(
          () => createPipeServerInstance(ep.address, sid: sid, first: true),
          throwsA(isA<WinPipeException>()
              .having((e) => e.code, 'code', WinError.accessDenied)));
    });

    test('transport round trip (multibyte), then the server is gone',
        () async {
      final ep = testEndpoint();
      final server =
          serveOnce(ep.address, currentUserSid(), reply: echoReply);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(await WindowsPipeTransport().roundTrip(ep, 'hello'),
          'echo:hello \u00e9\u{1F600}');
      await server;
      expect(await WindowsPipeTransport().probe(ep), isFalse);
    });

    test('server closing without a reply is a lost connection', () async {
      final ep = testEndpoint();
      final server = serveOnce(ep.address, currentUserSid(), reply: noReply);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await expectLater(WindowsPipeTransport().roundTrip(ep, 'x'),
          throwsA(isA<CliConnectionLost>()));
      await server;
    });

    test('no reply before the timeout raises CliTimeout', () async {
      final ep = testEndpoint();
      final sid = currentUserSid();
      final pipe = createPipeServerInstance(ep.address, sid: sid, first: true);
      addTearDown(() => closeWinHandle(pipe));
      await expectLater(
          WindowsPipeTransport(timeout: const Duration(milliseconds: 500))
              .roundTrip(ep, 'x'),
          throwsA(isA<CliTimeout>()));
    });

    test('oversized response is a protocol error', () async {
      final ep = testEndpoint();
      final server = serveOnce(ep.address, currentUserSid(), replyBytes: 5000);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await expectLater(
          WindowsPipeTransport(maxResponseBytes: 1000).roundTrip(ep, 'x'),
          throwsA(isA<CliProtocolException>()));
      await server;
    });

    test('the server sees its client as the current user', () async {
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
  });
}
