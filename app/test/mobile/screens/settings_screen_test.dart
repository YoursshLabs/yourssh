import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';

Future<void> _pump(WidgetTester tester) async {
  final settings = SettingsProvider();
  final sync = SyncProvider();

  await tester.pumpWidget(
    MaterialApp(
      theme: buildMobileTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
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
}
