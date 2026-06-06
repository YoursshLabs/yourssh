import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/agent_status_line.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester,
      {Host? existing,
      Future<AgentProbeResult> Function()? agentProbe}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HostDetailPanel(
              existing: existing,
              agentProbe: agentProbe ?? () async => const AgentProbeSystem(1),
              onClose: () {},
              onSave: (host, _) async => saved = host,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Host existingHost({bool agentForwarding = false}) => Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'root',
        agentForwarding: agentForwarding,
      );

  testWidgets('toggle defaults off and saves true after switching on',
      (tester) async {
    await pumpPanel(tester, existing: existingHost());

    final toggle = find.widgetWithText(SwitchListTile, 'Agent forwarding');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.agentForwarding, isTrue);
  });

  testWidgets('editing a host with forwarding on shows the switch on',
      (tester) async {
    await pumpPanel(tester, existing: existingHost(agentForwarding: true));

    final toggle = find.widgetWithText(SwitchListTile, 'Agent forwarding');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('status line appears when the toggle is switched on',
      (tester) async {
    await pumpPanel(tester,
        existing: existingHost(),
        agentProbe: () async => const AgentProbeKeychain(2));
    expect(find.byType(AgentStatusLine), findsNothing);

    final toggle = find.widgetWithText(SwitchListTile, 'Agent forwarding');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      find.text(
          'No system agent — 2 app Keychain keys will be offered instead'),
      findsOneWidget,
    );
  });

  testWidgets('only one status line when auth is SSH Agent and forwarding on',
      (tester) async {
    await pumpPanel(tester, existing: existingHost(agentForwarding: true));
    expect(find.byType(AgentStatusLine), findsOneWidget);

    final dropdown = find.byType(DropdownButton<AuthType>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH Agent').last);
    await tester.pumpAndSettle();

    expect(find.byType(AgentStatusLine), findsOneWidget);
  });

  testWidgets('info tooltip explains agent auth vs forwarding',
      (tester) async {
    await pumpPanel(tester, existing: existingHost());
    final tooltip = find.byWidgetPredicate((w) =>
        w is Tooltip && (w.message ?? '').startsWith('SSH Agent auth:'));
    expect(tooltip, findsOneWidget);
  });
}
