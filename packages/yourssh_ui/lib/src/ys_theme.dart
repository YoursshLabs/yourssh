import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

FColors _ysColors(FColors base) => base.copyWith(
  background: YsColors.background,
  foreground: YsColors.foreground,
  primary: YsColors.primary,
  primaryForeground: YsColors.primaryForeground,
  secondary: YsColors.secondary,
  secondaryForeground: YsColors.foreground,
  muted: YsColors.muted,
  mutedForeground: YsColors.mutedForeground,
  border: YsColors.border,
  card: YsColors.card,
  destructive: YsColors.error,
);

FThemeData _build({required bool touch}) {
  final base = touch ? FTheme.neutral.dark.touch : FTheme.neutral.dark.desktop;
  final colors = _ysColors(base.colors);
  final face = FTypeface.inherit(
    colors: colors,
    touch: touch,
    fontFamily: kYsFontFamily,
  );
  return FThemeData(
    colors: colors,
    touch: touch,
    typography: FTypography(display: face, body: face),
  );
}

/// forui theme (desktop sizing) with Amber Brand tokens.
FThemeData ysThemeData() => _build(touch: false);

/// forui theme (touch sizing) with Amber Brand tokens, for mobile.
FThemeData ysThemeDataTouch() => _build(touch: true);

/// Material fallback theme so un-migrated widgets match the system.
ThemeData ysMaterialTheme() {
  final scheme = const ColorScheme.dark().copyWith(
    primary: YsColors.primary,
    onPrimary: YsColors.primaryForeground,
    surface: YsColors.background,
    onSurface: YsColors.foreground,
    error: YsColors.error,
  );
  RoundedRectangleBorder shape(double r, {bool side = true}) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r),
        side: side ? const BorderSide(color: YsColors.border) : BorderSide.none,
      );
  OutlineInputBorder input(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(YsRadius.control),
    borderSide: BorderSide(color: c),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: kYsFontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: YsColors.background,
    dividerColor: YsColors.border,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: YsColors.card,
        border: Border.all(color: YsColors.border),
        borderRadius: BorderRadius.circular(YsRadius.control),
      ),
      textStyle: const TextStyle(color: YsColors.foreground, fontSize: 12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: YsColors.card,
      shape: shape(YsRadius.card),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: YsColors.card,
      shape: shape(YsRadius.card, side: false),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: YsColors.card,
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: YsColors.secondary,
      border: input(Colors.transparent),
      enabledBorder: input(Colors.transparent),
      focusedBorder: input(YsColors.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(YsColors.foreground),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? YsColors.primary : null,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: YsColors.primary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: YsColors.primary,
        foregroundColor: YsColors.primaryForeground,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: YsColors.border),
      ),
    ),
  );
}
