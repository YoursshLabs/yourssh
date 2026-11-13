import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/workspace_side_panel.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  Widget wrap({VoidCallback? onClose, Widget? headerExtra}) => ysTestApp(
        Row(children: [
          WorkspaceSidePanel(
            title: 'Things',
            closeTooltip: 'Close things',
            onClose: onClose,
            headerExtra: headerExtra,
            child: const Text('panel body'),
          ),
        ]),
      );

  testWidgets('renders title, header extra and body', (tester) async {
    await tester.pumpWidget(wrap(headerExtra: const Text('extra')));
    expect(find.text('Things'), findsOneWidget);
    expect(find.text('extra'), findsOneWidget);
    expect(find.text('panel body'), findsOneWidget);
    expect(tester.getSize(find.byType(WorkspaceSidePanel)).width, 340);
  });

  testWidgets('close is a forui button with a tooltip and fires onClose',
      (tester) async {
    var closed = 0;
    await tester.pumpWidget(wrap(onClose: () => closed++));
    expect(find.byTooltip('Close things'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(WorkspaceSidePanel), matching: find.byType(FButton)),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close things'));
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('no close button without onClose', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.byTooltip('Close things'), findsNothing);
  });

  testWidgets('frame is painted with the design tokens', (tester) async {
    await tester.pumpWidget(wrap());
    final box = tester.widget<DecoratedBox>(find
        .descendant(
            of: find.byType(WorkspaceSidePanel),
            matching: find.byType(DecoratedBox))
        .first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, YsColors.card);
  });
}
