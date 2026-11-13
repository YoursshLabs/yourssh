// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Test host mirroring the app root: Material theme plus the FTheme/FToaster
/// wrapping the app's `ysRootBuilder` provides.
Widget ysTestApp(Widget child) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) => FTheme(
    data: ysThemeData(),
    child: FToaster(child: child ?? const SizedBox.shrink()),
  ),
  home: Scaffold(body: child),
);

/// Pushes [screen] as a route on a bare MaterialApp (no root builder), the
/// way a host without `ysRootBuilder` would, and settles.
Future<void> pumpPushedRoute(
  WidgetTester tester,
  Widget Function(BuildContext) screen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (ctx) => Scaffold(body: screen(ctx)),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
