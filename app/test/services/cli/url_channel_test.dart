import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/cli_handlers.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh/services/cli/host_resolver.dart';
import 'package:yourssh/services/cli/url_channel.dart';

class _Fake implements CliHandlers {
  @override
  List<Host> hosts = [Host(id: 'a', label: 'web-1', host: 'h', username: 'u')];
  final calls = <String>[];
  @override
  Future<void> connect(Host host, {required String source}) async =>
      calls.add('connect:${host.label}:$source');
  @override
  Future<void> connectAdHoc(AdHocTarget t) async => calls.add('adhoc');
  @override
  Future<void> focusWindow() async => calls.add('focus');
  @override
  String get appVersion => '1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('yourssh/url');
  late _Fake fake;

  setUp(() => fake = _Fake());
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, null));

  Future<void> send(String url) => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .handlePlatformMessage(
          'yourssh/url',
          const StandardMethodCodec().encodeMethodCall(MethodCall('open', url)),
          (_) {});

  test('a yourssh://connect URL reaches the server as a trusted open',
      () async {
    final u = UrlChannel(
        server: CliServer(handlers: fake, token: 't'), channel: ch);
    u.attach();
    await send('yourssh://connect/web-1');
    await pumpEventQueue();
    expect(fake.calls, ['connect:web-1:url']);
  });

  test('yourssh://exec/x does not connect', () async {
    final u = UrlChannel(
        server: CliServer(handlers: fake, token: 't'), channel: ch);
    u.attach();
    await send('yourssh://exec/x');
    await pumpEventQueue();
    expect(fake.calls, isEmpty);
  });

  test('opens wait for the ready gate (hosts loaded)', () async {
    final gate = Completer<void>();
    final u = UrlChannel(
        server: CliServer(handlers: fake, token: 't'),
        channel: ch,
        ready: gate.future);
    u.attach();
    final sent = send('yourssh://connect/web-1');
    await pumpEventQueue();
    expect(fake.calls, isEmpty);
    gate.complete();
    await sent;
    await pumpEventQueue();
    expect(fake.calls, ['connect:web-1:url']);
  });

  test('attach tells native the Dart side is listening', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (c) async => calls.add(c.method));
    UrlChannel(server: CliServer(handlers: fake, token: 't'), channel: ch)
        .attach();
    await pumpEventQueue();
    expect(calls, ['ready']);
  });

  test('openLaunchUrl opens the first yourssh:// argv entry (cold start)',
      () async {
    final u = UrlChannel(
        server: CliServer(handlers: fake, token: 't'), channel: ch);
    await u.openLaunchUrl(['--x', 'yourssh://connect/web-1']);
    expect(fake.calls, ['connect:web-1:url']);
    fake.calls.clear();
    await u.openLaunchUrl(['nothing']);
    expect(fake.calls, isEmpty);
  });

  group('hardening', () {
    UrlChannel mk({Future<void>? ready, DateTime Function()? now}) =>
        UrlChannel(
            server: CliServer(handlers: fake, token: 't'),
            channel: ch,
            ready: ready,
            now: now ?? DateTime.now);

    test('hostile and unknown URLs open nothing; scheme is case-insensitive',
        () async {
      final u = mk();
      for (final url in [
        'yourssh://connect/a/b',
        'yourssh://connect/x?cmd=1',
        'yourssh://connect/a%2Fb',
        'yourssh://connect/user@evil.example',
        'yourssh://connect/no-such-host',
      ]) {
        await u.open(url);
      }
      expect(fake.calls, isEmpty);
      await u.open('YOURSSH://connect/web-1');
      expect(fake.calls, ['connect:web-1:url']);
    });

    test('a repeat of the same URL within 2 s is dropped, then allowed',
        () async {
      var t = DateTime(2026, 1, 1);
      final u = mk(now: () => t);
      await u.open('yourssh://connect/web-1');
      t = t.add(const Duration(seconds: 1));
      await u.open('yourssh://connect/web-1');
      expect(fake.calls, ['connect:web-1:url']);
      t = t.add(const Duration(seconds: 2));
      await u.open('yourssh://connect/web-1');
      expect(fake.calls.length, 2);
    });

    test('a failing ready gate drops the URL without throwing', () async {
      final u = mk(ready: Future<void>.error(StateError('load failed')));
      await u.open('yourssh://connect/web-1');
      expect(fake.calls, isEmpty);
    });
  });
}
