import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _wrap(Widget child, {double width = 800}) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) => FTheme(data: ysThemeData(), child: child!),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('is a 22 px chrome strip', (tester) async {
    await tester.pumpWidget(
      _wrap(const YsStatusBar(leading: [Text('Connected')])),
    );
    final bar = find.byType(YsStatusBar);
    expect(tester.getSize(bar).height, 22);
    final box = tester.widget<ColoredBox>(
      find.byKey(const Key('ys-status-bar')),
    );
    expect(box.color, YsColors.chrome);
  });

  testWidgets('text is 11 px monospace, muted by default', (tester) async {
    await tester.pumpWidget(
      _wrap(const YsStatusBar(leading: [Text('Connected')])),
    );
    final style = DefaultTextStyle.of(tester.element(find.text('Connected')))
        .style;
    expect(style.fontSize, 11);
    expect(style.fontFamily, kYsMonoFontFamily);
    expect(style.fontFamilyFallback, kYsMonoFontFallback);
    expect(style.color, YsColors.mutedForeground);
  });

  testWidgets('leading starts at the left edge, trailing ends at the right', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const YsStatusBar(
          leading: [Text('left-a'), Text('left-b')],
          trailing: [Text('right-a'), Text('right-b')],
        ),
      ),
    );
    final bar = tester.getRect(find.byType(YsStatusBar));
    final leftA = tester.getRect(find.text('left-a'));
    final leftB = tester.getRect(find.text('left-b'));
    final rightB = tester.getRect(find.text('right-b'));
    expect(leftA.left - bar.left, lessThanOrEqualTo(YsSpace.s3));
    expect(leftB.left, greaterThan(leftA.right));
    expect(bar.right - rightB.right, lessThanOrEqualTo(YsSpace.s3));
  });

  testWidgets('long content clips instead of overflowing', (tester) async {
    await tester.pumpWidget(
      _wrap(
        YsStatusBar(
          leading: [for (var i = 0; i < 6; i++) YsStatusItem(label: 'x' * 60)],
          trailing: [for (var i = 0; i < 6; i++) YsStatusItem(label: 'y' * 30)],
        ),
        width: 300,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  group('YsStatusItem', () {
    testWidgets('draws a status dot in dotColor before the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const YsStatusBar(
            leading: [YsStatusItem(label: 'Connected', dotColor: YsColors.ok)],
          ),
        ),
      );
      final dot = tester.widget<DecoratedBox>(
        find.byKey(const Key('ys-status-dot')),
      );
      expect((dot.decoration as BoxDecoration).color, YsColors.ok);
      expect(
        tester.getRect(find.byKey(const Key('ys-status-dot'))).right,
        lessThan(tester.getRect(find.text('Connected')).left),
      );
    });

    testWidgets('shows an icon and colours the label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const YsStatusBar(
            leading: [
              YsStatusItem(
                label: 'agent',
                icon: FLucideIcons.keyRound,
                color: YsColors.accentText,
              ),
            ],
          ),
        ),
      );
      expect(find.byIcon(FLucideIcons.keyRound), findsOneWidget);
      final text = tester.widget<Text>(find.text('agent'));
      expect(text.style?.color, YsColors.accentText);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('wraps itself in a tooltip when given one', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const YsStatusBar(
            leading: [YsStatusItem(label: 'Error', tooltip: 'Auth failed')],
          ),
        ),
      );
      expect(find.byTooltip('Auth failed'), findsOneWidget);
    });

    testWidgets('caps the label width with an ellipsis', (tester) async {
      await tester.pumpWidget(
        _wrap(
          YsStatusBar(
            leading: [YsStatusItem(label: 'z' * 200, maxLabelWidth: 120)],
          ),
        ),
      );
      expect(
        tester.getSize(find.text('z' * 200)).width,
        lessThanOrEqualTo(120),
      );
    });
  });
}
