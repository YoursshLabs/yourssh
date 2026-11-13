import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _host(void Function(BuildContext) onTap) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) =>
      FTheme(data: ysThemeData(), child: FToaster(child: child!)),
  home: Scaffold(
    body: Builder(
      builder: (c) => TextButton(onPressed: () => onTap(c), child: const Text('go')),
    ),
  ),
);

Future<void> _fire(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  for (final kind in YsToastKind.values) {
    testWidgets('$kind toast shows its message', (tester) async {
      await tester.pumpWidget(
        _host((c) => showYsToast(c, 'hello $kind', kind: kind)),
      );
      await _fire(tester);
      expect(find.text('hello $kind'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  }

  testWidgets('error shows an alert icon, info none', (tester) async {
    await tester.pumpWidget(
      _host((c) => showYsToast(c, 'bad', kind: YsToastKind.error)),
    );
    await _fire(tester);
    expect(find.byIcon(FLucideIcons.circleAlert), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('action button fires onAction', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      _host(
        (c) => showYsToast(
          c,
          'with action',
          actionLabel: 'Undo',
          onAction: () => fired++,
        ),
      ),
    );
    await _fire(tester);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(fired, 1);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('toast disappears after its duration', (tester) async {
    await tester.pumpWidget(
      _host(
        (c) => showYsToast(c, 'brief', duration: const Duration(seconds: 2)),
      ),
    );
    await _fire(tester);
    expect(find.text('brief'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('brief'), findsNothing);
  });

  testWidgets('default durations: info 3s, error 5s', (tester) async {
    await tester.pumpWidget(
      _host((c) {
        showYsToast(c, 'info-msg');
        showYsToast(c, 'err-msg', kind: YsToastKind.error);
      }),
    );
    await _fire(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('info-msg'), findsNothing);
    expect(find.text('err-msg'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('err-msg'), findsNothing);
  });
}
