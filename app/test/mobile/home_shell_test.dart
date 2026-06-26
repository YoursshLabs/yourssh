import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/mobile_tab_bar.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Widget _wrap(Widget child) {
  final storage = StorageService();
  final sync = SyncProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<KnownHostsProvider>(
        create: (_) => KnownHostsProvider.forTest([]),
      ),
      ChangeNotifierProvider<HostProvider>(
        create: (_) => HostProvider(storage),
      ),
      ChangeNotifierProvider<KeyProvider>(
        create: (_) => KeyProvider(),
      ),
      ChangeNotifierProvider<SessionProvider>(
        create: (_) =>
            SessionProvider(SshService(storage), TabMetadataService()),
      ),
      ChangeNotifierProvider<SnippetProvider>(
        create: (_) => SnippetProvider(),
      ),
      ChangeNotifierProvider<SettingsProvider>(
        create: (_) => SettingsProvider(),
      ),
      ChangeNotifierProvider<SyncProvider>.value(value: sync),
      Provider<SyncService>(create: (_) => SyncService(sync)),
      Provider<KeyGenService>(create: (_) => KeyGenService()),
      Provider<SshService>(create: (_) => SshService(storage)),
    ],
    child: MaterialApp(
      theme: buildMobileTheme(),
      home: child,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows four tab labels in MobileTabBar', (tester) async {
    await tester.pumpWidget(_wrap(const MobileHomeShell()));
    await tester.pumpAndSettle();

    final bar = find.byType(MobileTabBar);
    expect(bar, findsOneWidget);

    for (final label in ['Hosts', 'Snippets', 'Keys', 'Settings']) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
        reason: '$label tab label not found',
      );
    }
  });

  testWidgets('tapping Keys tab switches IndexedStack index', (tester) async {
    await tester.pumpWidget(_wrap(const MobileHomeShell()));
    await tester.pumpAndSettle();

    // Initially on Hosts (index 0)
    final stackBefore = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackBefore.index, 0);

    // Tap the Keys tab label in the tab bar
    final keysTabLabel = find.descendant(
      of: find.byType(MobileTabBar),
      matching: find.text('Keys'),
    );
    await tester.tap(keysTabLabel);
    await tester.pumpAndSettle();

    // IndexedStack now shows Keys at index 2
    final stackAfter = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stackAfter.index, MobileTab.values.indexOf(MobileTab.keys));
  });

  testWidgets('uses MobileTabBar not NavigationBar', (tester) async {
    await tester.pumpWidget(_wrap(const MobileHomeShell()));
    await tester.pumpAndSettle();

    expect(find.byType(MobileTabBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
