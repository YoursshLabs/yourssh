import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) =>
      FTheme(data: ysThemeData(), child: child!),
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
        YsTab(label: const Text('prod'), active: false, onMiddleClick: () => fired++),
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
    expect(find.byType(FButton), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('prod')));
    await tester.pump();

    expect(find.byType(FButton), findsOneWidget);
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
}
