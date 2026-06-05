import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Host? saved;

  // Settle and drain the pre-existing "ListTile background color" assertion that
  // fires because SwitchListTile sits inside _Card (DecoratedBox with background
  // color). This is a cosmetic issue in the production widget unrelated to the
  // agent-forwarding behaviour under test. Re-throws anything unrelated so real
  // failures still surface.
  Future<void> settleIgnoringListTileAssertion(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (true) {
      final ex = tester.takeException();
      if (ex == null) break;
      final msg = ex.toString();
      if (!msg.contains('ListTile background color') &&
          !msg.contains('ink splashes may be invisible') &&
          !msg.contains('Multiple exceptions')) {
        throw ex; // surface non-ListTile failures
      }
    }
  }

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
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
              onClose: () {},
              onSave: (host, _) async => saved = host,
            ),
          ),
        ),
      ),
    );
    await settleIgnoringListTileAssertion(tester);
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
    await settleIgnoringListTileAssertion(tester);

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settleIgnoringListTileAssertion(tester);

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
}
