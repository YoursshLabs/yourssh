import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_sync_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

Future<void> _pump(
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

  final sync = SyncProvider();
  if (status != SyncStatus.idle) sync.setStatus(status);

  final hosts = HostProvider(StorageService());

  await tester.pumpWidget(
    MaterialApp(
      theme: buildMobileTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
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
}
