import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';

Future<void> _pump(WidgetTester tester, SyncProvider sync) async {
  final storage = StorageService();
  await tester.pumpWidget(MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider(create: (_) => HostProvider(storage)),
        Provider<SyncService>(create: (_) => SyncService(sync)),
      ],
      child: const MobileSettingsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saving cloud config writes to the provider', (tester) async {
    final sync = SyncProvider();
    await _pump(tester, sync);

    await tester.enterText(
        find.byKey(const Key('sync-url')), 'https://x.supabase.co');
    await tester.enterText(find.byKey(const Key('sync-anon')), 'anon-key-123');
    await tester.enterText(find.byKey(const Key('sync-code')), '123456789012');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(sync.supabaseUrl, 'https://x.supabase.co');
    expect(sync.supabaseAnonKey, 'anon-key-123');
    expect(sync.syncCode, '123456789012');
  });
}
