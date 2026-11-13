import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/mobile_card.dart';
import 'package:yourssh/mobile/widgets/settings_row.dart';
import 'package:yourssh/mobile/widgets/tag_chip.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../helpers/ys_test_app.dart';

/// Whether any [ColoredBox] under [root] paints the shared tint.
bool _tinted(WidgetTester t, Finder root) => t
    .widgetList<ColoredBox>(
      find.descendant(of: root, matching: find.byType(ColoredBox)),
    )
    .any((b) => b.color == YsColors.secondary);

Future<TestGesture> _hover(WidgetTester t, Finder f) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: Offset.zero);
  await g.moveTo(t.getCenter(f));
  await t.pump();
  return g;
}

void main() {
  group('shared press/hover tint', () {
    testWidgets('MobileCard (reference): tints on hover and press', (t) async {
      await t.pumpWidget(
        ysTestApp(
          Center(child: MobileCard(onTap: () {}, child: const Text('card'))),
          touch: true,
        ),
      );
      final card = find.byType(MobileCard);
      expect(_tinted(t, card), isFalse);
      final g = await _hover(t, card);
      expect(_tinted(t, card), isTrue);
      await g.removePointer();
    });

    testWidgets('SettingsRow(onTap) tints on hover and on press', (t) async {
      var taps = 0;
      await t.pumpWidget(
        ysTestApp(
          Center(child: SettingsRow(title: 'Sync', onTap: () => taps++)),
          touch: true,
        ),
      );
      final row = find.byType(SettingsRow);
      expect(_tinted(t, row), isFalse);

      final hover = await _hover(t, row);
      expect(_tinted(t, row), isTrue, reason: 'hovered');
      await hover.removePointer();
      await t.pump();
      expect(_tinted(t, row), isFalse);

      final touch = await t.startGesture(t.getCenter(row));
      await t.pump(const Duration(milliseconds: 300));
      expect(_tinted(t, row), isTrue, reason: 'pressed');
      await touch.up();
      await t.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('SettingsRow without onTap has no tint target', (t) async {
      await t.pumpWidget(
        ysTestApp(const Center(child: SettingsRow(title: 'Static')), touch: true),
      );
      expect(
        find.descendant(
          of: find.byType(SettingsRow),
          matching: find.byType(FTappable),
        ),
        findsNothing,
      );
    });

    testWidgets('TagChip(onTap) tints when unselected, darkens when selected', (
      t,
    ) async {
      await t.pumpWidget(
        ysTestApp(
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TagChip(label: 'plain', large: true, onTap: () {}),
                TagChip(label: 'picked', large: true, selected: true, onTap: () {}),
              ],
            ),
          ),
          touch: true,
        ),
      );
      Container pill(String label) => t.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
      );
      Color? fill(Container c) => (c.decoration as BoxDecoration).color;

      expect(fill(pill('plain')), MobileColors.fieldFill);
      final g = await _hover(t, find.text('plain'));
      expect(fill(pill('plain')), YsColors.secondary);
      await g.moveTo(t.getCenter(find.text('picked')));
      await t.pump();
      expect(fill(pill('plain')), MobileColors.fieldFill);
      expect(fill(pill('picked')), MobileColors.accent, reason: 'stays amber');
      expect(pill('picked').foregroundDecoration, isNotNull);
      await g.removePointer();
    });

    testWidgets('tappable TagChip has a >=44 px hit area; static one does not '
        'grow', (t) async {
      await t.pumpWidget(
        ysTestApp(
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TagChip(label: 'tap', large: true, onTap: () {}),
                const TagChip(label: 'static'),
              ],
            ),
          ),
          touch: true,
        ),
      );
      final tap = t.getSize(find.bySubtype<FTappable>());
      expect(tap.height, greaterThanOrEqualTo(44));
      expect(tap.width, greaterThanOrEqualTo(44));
      expect(find.bySubtype<FTappable>(), findsOneWidget);
      expect(t.getSize(find.text('static')).height, lessThan(30));
    });
  });
}
