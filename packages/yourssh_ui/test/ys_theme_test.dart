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

  test('material colour scheme has no stock Material leaks', () {
    final s = ysMaterialTheme().colorScheme;
    final slots = <String, Color>{
      'primary': s.primary,
      'onPrimary': s.onPrimary,
      'primaryContainer': s.primaryContainer,
      'onPrimaryContainer': s.onPrimaryContainer,
      'secondary': s.secondary,
      'onSecondary': s.onSecondary,
      'secondaryContainer': s.secondaryContainer,
      'onSecondaryContainer': s.onSecondaryContainer,
      'tertiary': s.tertiary,
      'onTertiary': s.onTertiary,
      'tertiaryContainer': s.tertiaryContainer,
      'onTertiaryContainer': s.onTertiaryContainer,
      'error': s.error,
      'onError': s.onError,
      'errorContainer': s.errorContainer,
      'onErrorContainer': s.onErrorContainer,
      'surface': s.surface,
      'onSurface': s.onSurface,
      'surfaceDim': s.surfaceDim,
      'surfaceBright': s.surfaceBright,
      'surfaceContainerLowest': s.surfaceContainerLowest,
      'surfaceContainerLow': s.surfaceContainerLow,
      'surfaceContainer': s.surfaceContainer,
      'surfaceContainerHigh': s.surfaceContainerHigh,
      'surfaceContainerHighest': s.surfaceContainerHighest,
      'onSurfaceVariant': s.onSurfaceVariant,
      'outline': s.outline,
      'outlineVariant': s.outlineVariant,
      'inverseSurface': s.inverseSurface,
      'onInverseSurface': s.onInverseSurface,
      'inversePrimary': s.inversePrimary,
      'surfaceTint': s.surfaceTint,
    };
    const stock = [0xFF03DAC6, 0xFFBB86FC, 0xFF121212];
    slots.forEach((name, c) {
      expect(stock.contains(c.toARGB32()), isFalse, reason: name);
    });
  });

  test('material text theme and divider restore develop sizes', () {
    final t = ysMaterialTheme();
    expect(t.textTheme.bodyMedium!.fontSize, 13);
    expect(t.textTheme.bodyMedium!.color, YsColors.foreground);
    expect(t.textTheme.bodySmall!.fontSize, 12);
    expect(t.textTheme.bodySmall!.color, YsColors.mutedForeground);
    expect(t.textTheme.labelMedium!.fontSize, 12);
    expect(t.textTheme.labelMedium!.color, YsColors.mutedForeground);
    expect(t.dividerTheme.thickness, 1);
    expect(t.dividerTheme.space, 1);
    expect(t.dividerTheme.color, YsColors.border);
  });

  test('theme builders are cached', () {
    expect(identical(ysThemeData(), ysThemeData()), isTrue);
    expect(identical(ysThemeDataTouch(), ysThemeDataTouch()), isTrue);
    expect(identical(ysMaterialTheme(), ysMaterialTheme()), isTrue);
  });
}
