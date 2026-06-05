import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/theme_picker.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: Center(child: child)));
  }

  testWidgets('mini swatch paints visible color stripes', (tester) async {
    await tester.pumpWidget(wrap(
      ThemePickerButton(currentTheme: 'Dracula', onChanged: (_) {}),
    ));

    final stripes = find.descendant(
      of: find.byType(ThemePickerButton),
      matching: find.byType(ColoredBox),
    );
    expect(stripes, findsNWidgets(4));
    for (final element in stripes.evaluate()) {
      final box = element.renderObject! as RenderBox;
      expect(box.size.height, greaterThan(0),
          reason: 'swatch stripe must have a visible height');
      expect(box.size.width, greaterThan(0),
          reason: 'swatch stripe must have a visible width');
    }
  });
}
