import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/mobile/screens/mobile_sync_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';

Future<SyncProvider> _pump(WidgetTester tester) async {
  final sync    = SyncProvider();
  final storage = StorageService();

  // Providers wrap MaterialApp so pushed routes (MobileSyncScreen) also find
  // them in the tree.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncProvider>.value(value: sync),
        ChangeNotifierProvider<HostProvider>.value(
          value: HostProvider(storage),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        Provider<SyncService>(create: (_) => SyncService(sync)),
      ],
      child: MaterialApp(
        theme: buildMobileTheme(),
        home: const MobileSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Scroll to ensure lazy list items below the fold are built.
  await tester.drag(find.byType(ListView), const Offset(0, -3000));
  await tester.pumpAndSettle();
  return sync;
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

  testWidgets('"Supabase sync" row navigates to MobileSyncScreen', (tester) async {
    await _pump(tester);

    // Tap the row — now pushes MobileSyncScreen instead of opening a sheet.
    await tester.tap(find.text('Supabase sync'));
    // Use pump(Duration) to avoid pumpAndSettle timing out on the P2P Timer.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // MobileSyncScreen heading must be visible.
    expect(find.text('Sync with Supabase'), findsOneWidget);
    expect(find.byType(MobileSyncScreen), findsOneWidget);
  });
}
