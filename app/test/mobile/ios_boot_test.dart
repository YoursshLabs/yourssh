import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/mobile_app.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';
import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/mobile/screens/mobile_keys_screen.dart';
import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/mobile/screens/mobile_snippets_screen.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
import 'package:yourssh/mobile/widgets/mobile_tab_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({kAppLockPrefKey: false});
    PackageInfo.setMockInitialValues(
      appName: 'YourSSH',
      packageName: 'com.thangnm.yourssh',
      version: '0.0.0',
      buildNumber: '0',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  testWidgets('the mobile shell boots under iOS',
      (t) async {
    await t.pumpWidget(const YourSSHMobileApp());
    await t.pumpAndSettle();
    expect(find.byType(MobileHomeShell), findsOneWidget);
    expect(find.byType(MobileTabBar), findsOneWidget);
    expect(t.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('every tab renders under iOS', (t) async {
    await t.pumpWidget(const YourSSHMobileApp());
    await t.pumpAndSettle();
    final screens = <String, Type>{
      'Snippets': MobileSnippetsScreen,
      'Keys': MobileKeysScreen,
      'Settings': MobileSettingsScreen,
      'Hosts': MobileHostsScreen,
    };
    for (final e in screens.entries) {
      await t.tap(find.descendant(
          of: find.byType(MobileTabBar), matching: find.text(e.key)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: e.key);
      // IndexedStack: only the selected tab is onstage.
      expect(find.byType(e.value), findsOneWidget, reason: e.key);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
