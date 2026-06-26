import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color palette for the mobile UI. Desktop theme ([AppColors]) is untouched.
abstract final class MobileColors {
  static const accent      = Color(0xFFF7A01A);
  static const accentSoft  = Color(0xFF2A2010);
  static const bg          = Color(0xFF000000);
  static const surface     = Color(0xFF161618);
  static const surfaceAlt  = Color(0xFF0C0C0E);
  static const border      = Color(0xFF232325);
  static const borderSoft  = Color(0xFF1A1A1C);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textMuted   = Color(0xFF8A8A8E);
  static const textFaint   = Color(0xFF5D5D63);
  static const green       = Color(0xFF22C55E);
  static const red         = Color(0xFFFF6464);
  static const blue        = Color(0xFF4DA3FF);
  static const yellow      = Color(0xFFFFCE35);
}

/// Builds the dark [ThemeData] used by the mobile UI.
/// Desktop theme is untouched; this is mobile-only.
ThemeData buildMobileTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: MobileColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: MobileColors.accent,
    surface: MobileColors.surface,
  );

  return ThemeData(
    colorScheme: base,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: MobileColors.bg,
    useMaterial3: true,
  );
}

/// Manrope — headings.
TextStyle mobileHeading({
  double size = 17,
  FontWeight weight = FontWeight.w600,
}) =>
    GoogleFonts.manrope(
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
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? MobileColors.textPrimary,
    );

/// Roboto Mono — monospace / code.
TextStyle mobileMono({
  double size = 13,
  Color? color,
  FontWeight? weight,
}) =>
    GoogleFonts.robotoMono(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? MobileColors.textPrimary,
    );
