import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  testWidgets('AppSnack.error shows a toast with its message', (tester) async {
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (c) => TextButton(
            onPressed: () => AppSnack.error(c, 'Boom'),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Boom'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('AppSnack.info / success show their messages', (tester) async {
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (c) => TextButton(
            onPressed: () {
              AppSnack.info(c, 'FYI');
              AppSnack.success(c, 'Done');
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('FYI'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('toast via the global navigator context renders', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        theme: ysMaterialTheme(),
        builder: ysRootBuilder,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final ctx = navKey.currentContext;
    expect(ctx, isNotNull);
    showYsToast(ctx!, 'global notice');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('global notice'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });
}
