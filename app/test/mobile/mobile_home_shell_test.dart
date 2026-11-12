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
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilderTouch;
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _wrap(Widget child, {bool withRoot = true}) {
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
      builder: withRoot ? ysRootBuilderTouch : null,
      home: child,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows MobileTabBar with four destinations', (tester) async {
    await tester.pumpWidget(_wrap(const MobileHomeShell()));
    await tester.pumpAndSettle();

    expect(find.byType(MobileTabBar), findsOneWidget);
    final bar = find.byType(MobileTabBar);
    for (final label in ['Hosts', 'Snippets', 'Keys', 'Settings']) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
      );
    }
  });

  testWidgets('a toast does not cover the MobileTabBar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const MobileHomeShell(), withRoot: true));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(MobileHomeShell));
    showYsToast(context, 'Saved');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final toast = find.ancestor(
      of: find.text('Saved'),
      matching: find.byType(FToast),
    );
    expect(toast, findsOneWidget);
    final toastRect = tester.getRect(toast);
    final barRect = tester.getRect(find.byType(MobileTabBar));
    expect(toastRect.overlaps(barRect), isFalse);
    expect(toastRect.bottom, lessThanOrEqualTo(barRect.top));
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('Settings tab is reachable', (tester) async {
    await tester.pumpWidget(_wrap(const MobileHomeShell()));
    await tester.pumpAndSettle();

    final bar = find.byType(MobileTabBar);
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();

    // Use firstWidget: TerminalAppearanceControls on the Settings screen renders
    // a DropdownButton which internally creates additional IndexedStack widgets.
    // The shell's IndexedStack is always the outermost (first) one in the tree.
    final stack = tester.firstWidget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, MobileTab.values.indexOf(MobileTab.settings));
  });
}
