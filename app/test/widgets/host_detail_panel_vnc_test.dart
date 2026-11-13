import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show FSwitch;

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Host? saved;

  setUp(() {
    saved = null;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpPanel(WidgetTester tester,
      {Host? existing, List<Host> allHosts = const []}) async {
    await tester.binding.setSurfaceSize(const Size(500, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hostProvider = HostProvider(StorageService());
    for (final h in allHosts) {
      await hostProvider.addHost(h);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>.value(value: hostProvider),
          Provider<SshService>(create: (_) => SshService(StorageService())),
        ],
        child: ysTestApp(
          HostDetailPanel(
            existing: existing,
            initialProtocol: existing == null ? HostProtocol.vnc : null,
            agentProbe: () async => const AgentProbeSystem(1),
            onClose: () {},
            onSave: (host, _) async => saved = host,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Host vncHost() => Host(
        id: 'vnc-1',
        label: 'desktop',
        host: '10.0.0.5',
        port: 5900,
        username: 'u',
        protocol: HostProtocol.vnc,
      );

  testWidgets('VNC mode hides SSH-only and RDP-only sections', (tester) async {
    await pumpPanel(tester, existing: vncHost());
    expect(find.text('VNC on'), findsOneWidget);
    expect(find.text('AUTH METHOD'), findsNothing);
    expect(find.text('RDP SECURITY'), findsNothing);
  });

  testWidgets('panel exposes a VNC protocol segment', (tester) async {
    await pumpPanel(tester);
    expect(find.text('VNC'), findsWidgets);
  });

  testWidgets('VNC mode shows the SSH TUNNEL dropdown', (tester) async {
    final bastion = Host(
        id: 'b1', label: 'bastion', host: '10.0.0.1', port: 22, username: 'u');
    await pumpPanel(tester, existing: vncHost(), allHosts: [bastion]);
    expect(find.text('SSH TUNNEL'), findsOneWidget);
  });

  testWidgets('remote clipboard switch defaults on and saves off when toggled',
      (tester) async {
    await pumpPanel(tester, existing: vncHost());
    final toggle = find.byKey(const ValueKey('remote-clipboard-switch'));
    await tester.ensureVisible(toggle);
    expect(tester.widget<FSwitch>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('host-save-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.remoteClipboard, isFalse);
  });
}
