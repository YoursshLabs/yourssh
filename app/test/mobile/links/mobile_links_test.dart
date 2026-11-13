import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/links/mobile_cli_handlers.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh/services/cli/host_resolver.dart';
import 'package:yourssh/services/cli/link_refused.dart';
import 'package:yourssh/services/cli/url_channel.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('yourssh/url');
  late HostProvider hosts;
  late List<String> opened;
  late List<String> refused;
  late DateTime clock;
  late CliServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    hosts = HostProvider(StorageService());
    await hosts.ready;
    await hosts.addHost(Host(label: 'Prod-DB', host: 'db.example.com', username: 'u'));
    await hosts.addHost(Host(label: 'DB', host: 'a.example.com', username: 'u'));
    await hosts.addHost(Host(label: 'db', host: 'b.example.com', username: 'u'));
    await hosts.addHost(Host(label: 'a', host: 'c.example.com', username: 'u'));
    opened = [];
    refused = [];
    clock = DateTime(2026);
    server = CliServer(
      handlers: MobileCliHandlers(
        hostProvider: hosts,
        open: (h, s) async => opened.add('${h.label}:$s'),
        appVersion: '1',
      ),
      token: 't',
      now: () => clock,
      onUrlRefused: (url, reason) {
        final n = linkRefusedNotification(url, reason);
        refused.add('${n.title} — ${n.body}');
      },
    );
    UrlChannel(server: server, channel: ch).attach();
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(ch, null));

  Future<void> send(String url) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            'yourssh/url',
            const StandardMethodCodec().encodeMethodCall(MethodCall('open', url)),
            (_) {});
    await pumpEventQueue();
  }

  test('yourssh://connect opens a saved host by label (NFC, any case)', () async {
    await send('yourssh://connect/prod-db');
    expect(opened, ['Prod-DB:url']);
  });

  test('unknown, ambiguous and unsupported links open nothing and are refused',
      () async {
    for (final u in [
      'yourssh://connect/nope',
      'yourssh://connect/db', // 'DB' + 'db'
      'yourssh://tunnel/start/x',
      'yourssh://connect/a?cmd=id',
      'yourssh://u@connect/a',
      'yourssh://connect/${'a' * 5000}',
    ]) {
      await send(u);
    }
    expect(opened, isEmpty);
    expect(refused, hasLength(6));
    // The 5000-char link and its reason are capped in what is shown.
    expect(refused.every((m) => m.length <= 120 + 200 + 40), isTrue);
  });

  test('control and bidi characters in a refused link never reach the message',
      () async {
    await send('yourssh://connect/x\u202e\x1b[31mevil');
    expect(opened, isEmpty);
    expect(refused, hasLength(1));
    expect(refused.single, contains('Link refused: yourssh://connect/x[31mevil'));
    expect(refused.single.contains('\u202e'), isFalse);
    expect(refused.single.contains('\x1b'), isFalse);
  });

  test('the same link twice within 2 s opens once', () async {
    await send('yourssh://connect/prod-db');
    await send('YOURSSH://connect/PROD-DB');
    expect(opened, ['Prod-DB:url']);
    clock = clock.add(CliServer.dedupeWindow);
    await send('yourssh://connect/prod-db');
    expect(opened, hasLength(2));
  });

  test('ad-hoc connects are impossible through the handlers', () async {
    final h = MobileCliHandlers(
        hostProvider: hosts, open: (_, _) async {}, appVersion: '1');
    expect(() => h.connectAdHoc(const AdHocTarget('a', 'h', 22)),
        throwsA(isA<StateError>()));
    await h.focusWindow(); // no-op
  });

}
