import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) => FTheme(data: ysThemeData(), child: child!),
  home: Scaffold(body: Row(children: [child])),
);

void main() {
  testWidgets('active tab shows the primary indicator on card background', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const YsTab(label: Text('prod'), active: true)),
    );
    expect(find.byKey(const Key('ys-tab-indicator')), findsOneWidget);
    final box = tester.widget<ColoredBox>(
      find.byKey(const Key('ys-tab-indicator')),
    );
    expect(box.color, YsColors.primary);
  });

  testWidgets('inactive tab has no indicator', (tester) async {
    await tester.pumpWidget(
      _wrap(const YsTab(label: Text('prod'), active: false)),
    );
    expect(find.byKey(const Key('ys-tab-indicator')), findsNothing);
  });

  testWidgets('middle click fires onMiddleClick', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      _wrap(
        YsTab(
          label: const Text('prod'),
          active: false,
          onMiddleClick: () => fired++,
        ),
      ),
    );
    final g = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kTertiaryButton,
    );
    await g.down(tester.getCenter(find.text('prod')));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(fired, 1);
  });

  testWidgets('close button shows on hover, has a tooltip, fires onClose', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      _wrap(
        YsTab(
          label: const Text('prod'),
          active: false,
          onClose: () => closed++,
          closeTooltip: 'Close tab',
        ),
      ),
    );
    expect(find.byType(FButton).hitTestable(), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('prod')));
    await tester.pump();

    expect(find.byType(FButton).hitTestable(), findsOneWidget);
    expect(find.byTooltip('Close tab'), findsOneWidget);
    await tester.tap(find.byType(FButton));
    await tester.pump();
    expect(closed, 1);
    await mouse.moveTo(const Offset(900, 700));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('close button is visible when active without hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        YsTab(
          label: const Text('prod'),
          active: true,
          onClose: () {},
          closeTooltip: 'Close tab',
        ),
      ),
    );
    expect(find.byType(FButton), findsOneWidget);
  });

  testWidgets('inactive tab width is identical before and after hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        YsTab(
          label: const Text('prod'),
          active: false,
          onClose: () {},
          closeTooltip: 'Close tab',
        ),
      ),
    );
    final before = tester.getSize(find.byType(YsTab));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('prod')));
    await tester.pump();
    expect(tester.getSize(find.byType(YsTab)), before);
    await mouse.moveTo(const Offset(900, 700));
    await tester.pump(const Duration(seconds: 1));
  });

  group('keyboard', () {
    testWidgets('Tab reaches the tab; Enter and Space select it', (t) async {
      var taps = 0;
      await t.pumpWidget(
        _wrap(
          YsTab(label: const Text('prod'), active: false, onTap: () => taps++),
        ),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(find.byKey(const Key('ys-tab-focus-ring')), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      expect(taps, 2);
    });

    testWidgets('inactive close button is inert until the tab has focus, '
        'then Tab reaches it and Enter closes', (t) async {
      var closed = 0;
      var taps = 0;
      final sem = t.ensureSemantics();
      await t.pumpWidget(
        _wrap(
          YsTab(
            label: const Text('prod'),
            active: false,
            onTap: () => taps++,
            onClose: () => closed++,
            closeTooltip: 'Close tab',
          ),
        ),
      );
      expect(find.byType(FButton).hitTestable(), findsNothing);
      expect(find.bySemanticsLabel('Close tab'), findsNothing);

      await t.sendKeyEvent(LogicalKeyboardKey.tab); // tab itself
      await t.pump();
      expect(find.byType(FButton).hitTestable(), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.tab); // close button
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(closed, 1);
      expect(taps, 0, reason: 'Enter on the close button must not select');
      sem.dispose();
    });
  });
}
