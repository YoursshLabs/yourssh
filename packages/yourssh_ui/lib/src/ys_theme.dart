// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
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
  destructiveForeground: YsColors.foreground,
  error: YsColors.error,
  errorForeground: YsColors.foreground,
);

FThemeData _build({required bool touch}) {
  final base = touch ? FTheme.neutral.dark.touch : FTheme.neutral.dark.desktop;
  final colors = _ysColors(base.colors);
  final face = FTypeface.inherit(
    colors: colors,
    touch: touch,
    fontFamily: kYsFontFamily,
  );
  final typography = FTypography(display: face, body: face);
  return FThemeData(
    colors: colors,
    touch: touch,
    typography: typography,
    sidebarStyle: _ysSidebarStyle(
      colors: colors,
      typography: typography,
      base: base,
      touch: touch,
    ),
  );
}

/// Width of the desktop app sidebar.
const double kYsSidebarWidth = 200;

/// Sidebar style: `sidebar` background, and the selected item is amber
/// (`primary` at 12% fill, primary icon and label). This is the one place
/// that style delta lives.
FSidebarStyle _ysSidebarStyle({
  required FColors colors,
  required FTypography typography,
  required FThemeData base,
  required bool touch,
}) {
  final inherited = FSidebarStyle.inherit(
    colors: colors,
    typography: typography,
    icons: base.icons,
    style: base.style,
    touch: touch,
  );
  final item = inherited.groupStyle.itemStyle;
  final selectedFill = YsColors.primary.withValues(alpha: 0.12);
  final itemStyle = item.copyWith(
    backgroundColor: .delta([
      .base(YsColors.sidebar),
      .match({FTappableVariant.disabled}, YsColors.sidebar),
      .exact({FTappableVariant.selected}, selectedFill),
    ]),
    textStyle: .delta([
      .exact({FTappableVariant.selected}, .delta(color: YsColors.primary)),
    ]),
    iconStyle: .delta([
      .exact({FTappableVariant.selected}, .delta(color: YsColors.primary)),
    ]),
  );
  return inherited.copyWith(
    decoration: .value(
      BoxDecoration(
        color: YsColors.sidebar,
        border: BorderDirectional(end: BorderSide(color: colors.border)),
      ),
    ),
    constraints: const BoxConstraints.tightFor(width: kYsSidebarWidth),
    groupStyle: .delta(itemStyle: itemStyle),
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
