import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/suggestion_popup.dart';

import '../helpers/ys_test_app.dart';

void main() {
  Widget wrap(Widget child) => ysTestApp(child);

  group('SuggestionPopup', () {
    testWidgets('renders all suggestions', (tester) async {
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: ['git status', 'git log', 'git diff'],
        selectedIndex: -1,
        onSelect: (_) {},
      )));
      expect(find.text('git status'), findsOneWidget);
      expect(find.text('git log'), findsOneWidget);
      expect(find.text('git diff'), findsOneWidget);
    });

    testWidgets('caps display at 8 items', (tester) async {
      final cmds = List.generate(10, (i) => 'cmd$i');
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: cmds,
        selectedIndex: -1,
        onSelect: (_) {},
        maxHeight: 400,
      )));
      for (int i = 0; i < 8; i++) {
        expect(find.text('cmd$i'), findsOneWidget);
      }
      expect(find.text('cmd8'), findsNothing);
      expect(find.text('cmd9'), findsNothing);
    });

    testWidgets('calls onSelect when item tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: ['git status', 'git log'],
        selectedIndex: -1,
        onSelect: (s) => selected = s,
      )));
      await tester.tap(find.text('git log'));
      expect(selected, 'git log');
    });

    testWidgets('selected item has the selection highlight background',
        (tester) async {
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: ['git status', 'git log'],
        selectedIndex: 0,
        onSelect: (_) {},
      )));
      final highlighted = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.color == kSuggestionSelectedColor;
      });
      expect(highlighted.length, 1);
    });
  });
}
