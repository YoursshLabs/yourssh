import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/mobile_tab_bar.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<KnownHostsProvider>(
          create: (_) => KnownHostsProvider.forTest([]),
        ),
      ],
      child: MaterialApp(
        theme: buildMobileTheme(),
        home: child,
      ),
    );

void main() {
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
