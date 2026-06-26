import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/util/mobile_prefs.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';

Future<void> _pump(WidgetTester tester) async {
  final settings = SettingsProvider();
  final sync     = SyncProvider();
  final storage  = StorageService();
  final hosts    = HostProvider(storage);
  final syncSvc  = SyncService(sync);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildMobileTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          Provider<SyncService>.value(value: syncSvc),
        ],
        child: const MobileSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Scroll to ensure all lazy list items are built.
  await tester.drag(find.byType(ListView), const Offset(0, -3000));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'YourSSH',
      packageName: 'com.yourssh',
      version: '1.2.3',
      buildNumber: '42',
      buildSignature: '',
      installerStore: null,
    );
  });

  testWidgets('renders TERMINAL section header', (tester) async {
    await _pump(tester);
    expect(find.text('TERMINAL'), findsOneWidget);
  });

  testWidgets('renders SECURITY section header', (tester) async {
    await _pump(tester);
    expect(find.text('SECURITY'), findsOneWidget);
  });

  testWidgets('renders KEYBOARD & SYNC section header', (tester) async {
    await _pump(tester);
    expect(find.text('KEYBOARD & SYNC'), findsOneWidget);
  });

  testWidgets('renders version string in footer', (tester) async {
    await _pump(tester);
    expect(find.textContaining('1.2.3'), findsOneWidget);
  });

  testWidgets('biometric toggle persists under kAppLockPrefKey', (tester) async {
    await _pump(tester);

    // SettingsRow renders a Row (not ListTile); find the Switch that sits in
    // the same Row ancestor as the "Biometric unlock" text.
    final biometricRow = find.ancestor(
      of: find.text('Biometric unlock'),
      matching: find.byType(Row),
    ).last; // innermost Row wrapping the row content
    final biometricSwitch = find.descendant(
      of: biometricRow,
      matching: find.byType(Switch),
    );
    expect(biometricSwitch, findsOneWidget);

    final initialValue = tester.widget<Switch>(biometricSwitch).value;
    await tester.tap(biometricSwitch);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAppLockPrefKey), !initialValue);
  });

  testWidgets('shortcut-bar toggle persists under kAccessoryBarPrefKey', (tester) async {
    await _pump(tester);

    // SettingsRow renders a Row (not ListTile); find the Switch that sits in
    // the same Row ancestor as the "Shortcut key bar" text.
    final shortcutRow = find.ancestor(
      of: find.text('Shortcut key bar'),
      matching: find.byType(Row),
    ).last;
    final shortcutSwitch = find.descendant(
      of: shortcutRow,
      matching: find.byType(Switch),
    );
    expect(shortcutSwitch, findsOneWidget);

    final initialValue = tester.widget<Switch>(shortcutSwitch).value;
    await tester.tap(shortcutSwitch);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAccessoryBarPrefKey), !initialValue);
  });
}
