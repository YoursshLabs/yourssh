// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

void main() {
  testWidgets("ysMaterialTheme() is flutter's ThemeData", (tester) async {
    late Color primary;
    await tester.pumpWidget(
      MaterialApp(
        theme: ysMaterialTheme(),
        home: Builder(
          builder: (context) {
            primary = Theme.of(context).colorScheme.primary;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(primary, YsColors.primary);
  });

  test('forui theme uses Amber tokens', () {
    expect(ysThemeData().colors.primary, YsColors.primary);
    expect(ysThemeData().colors.background, YsColors.background);
    expect(ysThemeDataTouch().colors.primary, YsColors.primary);
    expect(ysThemeData().colors.error, YsColors.error);
    expect(ysThemeData().colors.errorForeground, YsColors.foreground);
    expect(ysThemeData().colors.destructive, YsColors.error);
    expect(ysThemeData().colors.destructiveForeground, YsColors.foreground);
    expect(ysThemeData().typography.body.fontFamily, kYsFontFamily);
  });

  test('material theme uses Amber tokens', () {
    final t = ysMaterialTheme();
    expect(t.colorScheme.primary, YsColors.primary);
    expect(t.textTheme.bodyMedium!.fontFamily, 'Inter');
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, YsColors.background);
    expect(t.dividerColor, YsColors.border);
  });
}
