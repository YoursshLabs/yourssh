import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Color palette for the mobile UI. Desktop theme ([AppColors]) is untouched.
abstract final class MobileColors {
  static const accent      = YsColors.primary;
  static const accentSoft  = Color(0xFF2A2010);
  static const bg          = YsColors.background;
  static const surface     = YsColors.card;
  static const surfaceAlt  = YsColors.chrome;
  static const border      = YsColors.border;
  static const borderSoft  = Color(0x14FFEBD2);
  static const textPrimary = YsColors.foreground;
  static const textMuted   = YsColors.mutedForeground;
  static const textFaint   = Color(0xFF78716C);
  static const green       = YsColors.ok;
  static const red         = YsColors.error;
  static const blue        = Color(0xFF4DA3FF);
  static const yellow      = YsColors.warn;
  /// Input field fill color.
  static const fieldFill   = YsColors.secondary;
  /// Tab bar inactive icon/label color.
  static const tabInactive = Color(0xFF6D6D72);
}

/// Builds the dark [ThemeData] used by the mobile UI (shared Amber Brand
/// Material theme).
ThemeData buildMobileTheme() => ysMaterialTheme();

/// Inter 600 — headings.
TextStyle mobileHeading({
  double size = 17,
  FontWeight weight = FontWeight.w600,
}) =>
    TextStyle(
      fontFamily: kYsFontFamily,
      fontSize: size,
      fontWeight: weight,
      color: MobileColors.textPrimary,
    );

/// Inter — body / UI text.
TextStyle mobileBody({
  double size = 15,
  Color? color,
  FontWeight? weight,
}) =>
    TextStyle(
      fontFamily: kYsFontFamily,
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? MobileColors.textPrimary,
    );

/// Roboto Mono for Powerline (bundled) — monospace / code.
TextStyle mobileMono({
  double size = 13,
  Color? color,
  FontWeight? weight,
}) =>
    TextStyle(
      fontFamily: 'Roboto Mono for Powerline',
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? MobileColors.textPrimary,
    );
