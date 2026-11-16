// iOS simulator smoke test, run by the `ios` job in pr-test.yml:
//   flutter test integration_test/ios_smoke_test.dart -d <simulator udid>
//
// Boots the real mobile app with the app lock off, adds a host through
// HostProvider (no network is touched) and checks the card shows on the hosts
// tab, then opens Settings. Covers launch, bootstrap and tab navigation only;
// see the task report for what stays manual.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/mobile_app.dart';
import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/mobile/widgets/mobile_tab_bar.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches, lists an added host and opens Settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({kAppLockPrefKey: false});

    await tester.pumpWidget(const YourSSHMobileApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(MobileTabBar), findsOneWidget);

    final ctx = tester.element(find.byType(MobileTabBar));
    await ctx.read<HostProvider>().addHost(Host(
          label: 'smoke-host',
          host: '203.0.113.7',
          username: 'smoke',
        ));
    await tester.pumpAndSettle();

    expect(find.byType(HostCard), findsOneWidget);
    expect(find.text('smoke-host'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(MobileTabBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
