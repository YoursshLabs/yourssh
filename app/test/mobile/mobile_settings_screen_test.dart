import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';

Future<SyncProvider> _pump(WidgetTester tester) async {
  final sync    = SyncProvider();
  final storage = StorageService();

  // Providers must wrap MaterialApp (not just home:) so that modal bottom
  // sheets — which run in a separate overlay route — can still find them.
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

  testWidgets('saving cloud config writes to the provider', (tester) async {
    final sync = await _pump(tester);

    // Open the Supabase sync bottom sheet via the row tap.
    await tester.tap(find.text('Supabase sync'));
    await tester.pumpAndSettle();

    // The sheet fields are now visible.
    await tester.enterText(
        find.byKey(const Key('sync-url')), 'https://x.supabase.co');
    await tester.enterText(
        find.byKey(const Key('sync-anon')), 'anon-key-123');
    await tester.enterText(
        find.byKey(const Key('sync-code')), '123456789012');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(sync.supabaseUrl, 'https://x.supabase.co');
    expect(sync.supabaseAnonKey, 'anon-key-123');
    expect(sync.syncCode, '123456789012');
  });
}
