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

  testWidgets('Settings tab is reachable', (tester) async {
    await tester.pumpWidget(_wrap(const MobileHomeShell()));
    await tester.pumpAndSettle();

    final bar = find.byType(MobileTabBar);
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, MobileTab.values.indexOf(MobileTab.settings));
  });
}
