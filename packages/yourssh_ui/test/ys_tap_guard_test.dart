import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _app(Widget child, {bool touch = false}) => MaterialApp(
  home: FTheme(
    data: touch ? ysThemeDataTouch() : ysThemeData(),
    child: Scaffold(
      body: Center(child: SizedBox(width: 400, child: child)),
    ),
  ),
);

void main() {
  for (final touch in [false, true]) {
    testWidgets('password reveal toggle in an FTileGroup taps (touch=$touch)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          touch: touch,
          FTileGroup(
            children: [
              FTile.raw(
                child: FTextField.password(
                  control: .managed(
                    initial: const TextEditingValue(text: 'pw'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      EditableText editable() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(editable().obscureText, isTrue);
      await tester.tap(find.byType(FButton));
      await tester.pumpAndSettle();
      expect(editable().obscureText, isFalse);
    });
  }

  test('themes turn slideable tiles/items off', () {
    for (final t in [ysThemeData(), ysThemeDataTouch()]) {
      expect(t.tileGroupStyle.slideableTiles.resolve({}), isFalse);
      expect(t.itemGroupStyle.slideableItems.resolve({}), isFalse);
    }
  });
}
