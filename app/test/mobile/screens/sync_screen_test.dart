import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_sync_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

Future<SyncProvider> _pump(
  WidgetTester tester, {
  bool configured = true,
  SyncStatus status = SyncStatus.synced,
}) async {
  // Pre-seed SharedPreferences so SyncProvider._init() reads configured values.
  if (configured) {
    SharedPreferences.setMockInitialValues({
      'supabase_url': 'https://example.supabase.co',
      'supabase_anon_key': 'test-anon-key',
    });
  }

  final sync  = SyncProvider();
  if (status != SyncStatus.idle) sync.setStatus(status);

  final hosts    = HostProvider(StorageService());
  final syncSvc  = SyncService(sync);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildMobileTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          Provider<SyncService>.value(value: syncSvc),
        ],
        child: const MobileSyncScreen(),
      ),
    ),
  );

  // Pump a few frames to let initState + async SyncProvider._init() run, but
  // do NOT call pumpAndSettle — the P2P server's Timer.periodic would stall it
  // if the server happens to start successfully in the test environment.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));

  return sync;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders heading "Sync with Supabase"', (tester) async {
    await _pump(tester);
    expect(find.text('Sync with Supabase'), findsOneWidget);
  });

  testWidgets('renders "Scan QR code" button', (tester) async {
    await _pump(tester);
    // The button is at the bottom of the scrollable list — scroll to it.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Scan QR code'), findsOneWidget);
  });

  testWidgets('shows E2E badge when Supabase is configured', (tester) async {
    await _pump(tester, configured: true);
    expect(find.text('E2E'), findsOneWidget);
  });

  testWidgets('shows connected text when Supabase is configured', (tester) async {
    await _pump(tester, configured: true);
    expect(find.textContaining('connected'), findsWidgets);
  });

  testWidgets('hides E2E badge when Supabase is not configured', (tester) async {
    await _pump(tester, configured: false);
    expect(find.text('E2E'), findsNothing);
  });

  testWidgets('renders QR pairing caption', (tester) async {
    await _pump(tester);
    expect(find.textContaining('another device'), findsOneWidget);
  });

  // ── Config form: unconfigured state shows URL/anon/code fields ────────────

  testWidgets('shows config fields when Supabase is not configured',
      (tester) async {
    await _pump(tester, configured: false);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('sync-url')),  findsOneWidget);
    expect(find.byKey(const Key('sync-anon')), findsOneWidget);
    expect(find.byKey(const Key('sync-code')), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Pull from cloud'), findsOneWidget);
  });

  // ── Config form: Save round-trip calls setSupabaseConfig + setSyncCode ────

  testWidgets('Save calls setSupabaseConfig and setSyncCode on SyncProvider',
      (tester) async {
    final sync = await _pump(tester, configured: false);

    // Scroll config section into view.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 100));

    // Enter values into each field.
    await tester.enterText(
        find.byKey(const Key('sync-url')), 'https://my.supabase.co');
    await tester.enterText(
        find.byKey(const Key('sync-anon')), 'my-anon-key');
    await tester.enterText(
        find.byKey(const Key('sync-code')), 'ABCDEFGHIJKL');
    await tester.pump();

    // Ensure the Save button is scrolled into view before tapping.
    await tester.ensureVisible(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Save.
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify SyncProvider state was updated.
    expect(sync.supabaseUrl,     'https://my.supabase.co');
    expect(sync.supabaseAnonKey, 'my-anon-key');
    expect(sync.isSupabaseConfigured, isTrue);
  });

  // ── Config form: configured state shows "Edit credentials" affordance ─────

  testWidgets('shows Edit credentials button when already configured',
      (tester) async {
    await _pump(tester, configured: true);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Edit credentials'), findsOneWidget);
    // Fields are hidden until Edit is tapped.
    expect(find.byKey(const Key('sync-url')), findsNothing);
  });
}
