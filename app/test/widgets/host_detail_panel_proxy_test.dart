import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/proxy_settings.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Mock flutter_secure_storage so proxy-password persistence resolves
    // immediately instead of awaiting a platform reply that never arrives
    // under pumpAndSettle.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
          Provider<SshService>(create: (_) => SshService(StorageService())),
        ],
        child: ysTestApp(
          HostDetailPanel(
            existing: existing,
            agentProbe: () async => const AgentProbeSystem(1),
            onClose: () {},
            onSave: (host, _) async => saved = host,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('proxy dropdown defaults to None and hides fields', (tester) async {
    await pumpPanel(tester, existing: Host(label: 's', host: 'h', username: 'u'));
    final dropdown = find.byKey(const ValueKey('proxy-type-dropdown'));
    await tester.ensureVisible(dropdown);
    expect(find.byKey(const ValueKey('proxy-host-field')), findsNothing);
  });

  testWidgets('selecting HTTP reveals host/port and saving round-trips',
      (tester) async {
    await pumpPanel(tester, existing: Host(label: 's', host: 'h', username: 'u'));

    final dropdown = find.byKey(const ValueKey('proxy-type-dropdown'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTTP CONNECT').last);
    await tester.pumpAndSettle();

    final hostField = find.byKey(const ValueKey('proxy-host-field'));
    await tester.ensureVisible(hostField);
    await tester.enterText(hostField, 'proxy.local');
    await tester.enterText(
        find.byKey(const ValueKey('proxy-port-field')), '8080');

    final save = find.byKey(const ValueKey('host-save-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.proxyType, ProxyType.http);
    expect(saved!.proxyHost, 'proxy.local');
    expect(saved!.proxyPort, 8080);
  });
}
