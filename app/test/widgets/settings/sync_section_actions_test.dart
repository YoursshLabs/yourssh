import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_code.dart';
import 'package:yourssh/services/sync_service.dart';
import 'package:yourssh/widgets/settings/sync_section.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'settings_harness.dart';

class _FakeSyncService extends SyncService {
  _FakeSyncService(super.provider);
  int pushes = 0;

  @override
  Future<void> push({
    required List<Host> hosts,
    required Future<Map<String, String>> Function() loadPasswords,
  }) async => pushes++;
}

/// Sync section actions: Generate, Save code, reveal, Copy, Regenerate and
/// Disconnect (both branches of each confirm).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const code = 'ABCDEFGHJKMN';
  final secure = FakeSecureStore();
  late List<String> clipboard;

  setUp(() {
    mockPrefs({
      'supabase_url': 'https://abc.supabase.co',
      'supabase_anon_key': 'anon',
    });
    secure
      ..values.clear()
      ..failWrites = false
      ..install();
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() {
    secure.uninstall();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Finder byKey(String k) => find.byKey(ValueKey(k));

  Future<_FakeSyncService> pump(WidgetTester tester, SettingsHarness h) async {
    final svc = _FakeSyncService(h.sync);
    await h.pump(
      tester,
      MultiProvider(
        providers: [
          Provider<SyncService>.value(value: svc),
          ChangeNotifierProvider<HostProvider>(
            create: (_) => HostProvider(StorageService()),
          ),
        ],
        child: const SyncSettingsSection(),
      ),
    );
    return svc;
  }

  FButton buttonWith(WidgetTester tester, Finder text) => tester.widget(
    find.ancestor(of: text, matching: find.byType(FButton)).first,
  );

  testWidgets('Generate (no code yet) creates a code and pushes', (
    tester,
  ) async {
    final h = SettingsHarness();
    final svc = await pump(tester, h);
    expect(h.sync.hasSyncCode, isFalse);

    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(h.sync.hasSyncCode, isTrue);
    expect(SyncCode.isValid(h.sync.syncCode), isTrue);
    expect(secure.values['sync_code'], h.sync.syncCode);
    expect(svc.pushes, 1);
    expect(find.text('Regenerate sync code?'), findsNothing);
  });

  testWidgets('Save code stores a valid code and pushes', (tester) async {
    final h = SettingsHarness();
    final svc = await pump(tester, h);

    await tester.enterText(
      find.descendant(
        of: byKey('sync-code-field'),
        matching: find.byType(EditableText),
      ),
      'abcd-efgh-jkmn',
    );
    await tester.tap(byKey('sync-save-code'));
    await tester.pumpAndSettle();

    expect(h.sync.syncCode, code);
    expect(secure.values['sync_code'], code);
    expect(svc.pushes, 1);
  });

  testWidgets('Save code rejects an invalid code', (tester) async {
    final h = SettingsHarness();
    final svc = await pump(tester, h);

    await tester.enterText(
      find.descendant(
        of: byKey('sync-code-field'),
        matching: find.byType(EditableText),
      ),
      'short',
    );
    await tester.tap(byKey('sync-save-code'));
    await tester.pumpAndSettle();

    expect(h.sync.hasSyncCode, isFalse);
    expect(svc.pushes, 0);
    expect(find.text('Enter a valid 12-character sync code.'), findsOneWidget);
  });

  testWidgets('reveal toggle shows the code; Copy puts it on the clipboard', (
    tester,
  ) async {
    secure.values['sync_code'] = code;
    final h = SettingsHarness();
    await pump(tester, h);
    EditableText field() =>
        editableIn(tester, const ValueKey('sync-code-field'));

    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show sync code'));
    await tester.pumpAndSettle();
    expect(field().obscureText, isFalse);
    expect(field().controller.text, 'ABCD-EFGH-JKMN');
    await tester.tap(find.byTooltip('Hide sync code'));
    await tester.pumpAndSettle();
    expect(field().obscureText, isTrue);

    await tester.tap(byKey('sync-copy-code'));
    await tester.pumpAndSettle();
    expect(clipboard, [code]);
    expect(find.text('Sync code copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('Regenerate confirm replaces the code and pushes', (
    tester,
  ) async {
    secure.values['sync_code'] = code;
    final h = SettingsHarness();
    final svc = await pump(tester, h);

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regenerate').last);
    await tester.pumpAndSettle();

    expect(h.sync.syncCode, isNot(code));
    expect(SyncCode.isValid(h.sync.syncCode), isTrue);
    expect(svc.pushes, 1);
  });

  group('Disconnect', () {
    testWidgets('asks first; Cancel (default focus) keeps the config', (
      tester,
    ) async {
      secure.values['sync_code'] = code;
      final h = SettingsHarness();
      await pump(tester, h);

      await tester.tap(byKey('sync-disconnect'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect sync?'), findsOneWidget);
      expect(
        find.text(
          'This removes the Supabase URL, anon key and sync code from this '
          'device. Without the sync code the synced data can\'t be '
          'recovered — copy it first.',
        ),
        findsOneWidget,
      );
      expect(buttonWith(tester, find.text('Cancel')).autofocus, isTrue);
      final confirm = buttonWith(tester, find.text('Disconnect').last);
      expect(confirm.variant, FButtonVariant.destructive);
      expect(
        h.sync.isSupabaseConfigured,
        isTrue,
        reason: 'nothing cleared yet',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(h.sync.isSupabaseConfigured, isTrue);
      expect(h.sync.syncCode, code);
      expect(secure.values['sync_code'], code);
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('Confirm clears the config and the sync code', (tester) async {
      secure.values['sync_code'] = code;
      final h = SettingsHarness();
      await pump(tester, h);

      await tester.tap(byKey('sync-disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect').last);
      await tester.pumpAndSettle();

      expect(h.sync.isSupabaseConfigured, isFalse);
      expect(h.sync.syncCode, '');
      expect(secure.values.containsKey('sync_code'), isFalse);
      expect(find.text('Connected'), findsNothing);
    });
  });
}
