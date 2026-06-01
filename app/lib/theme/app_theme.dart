import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0F0F0F);
  static const sidebar = Color(0xFF141414);
  static const card = Color(0xFF1C1C1C);
  static const cardHover = Color(0xFF242424);
  static const border = Color(0xFF2A2A2A);
  static const accent = Color(0xFF22C55E);
  static const accentDim = Color(0xFF16A34A);
  static const textPrimary = Color(0xFFE5E5E5);
  static const textSecondary = Color(0xFF888888);
  static const textTertiary = Color(0xFF555555);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF97316);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF8B5CF6);

  static const hostColors = [
    Color(0xFFF97316), // orange
    Color(0xFF3B82F6), // blue
    Color(0xFF8B5CF6), // purple
    Color(0xFF06B6D4), // cyan
    Color(0xFFEC4899), // pink
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFF6366F1), // indigo
  ];

  static Color hostColor(String seed) {
    final idx = seed.codeUnits.fold(0, (a, b) => a + b) % hostColors.length;
    return hostColors[idx];
  }

  /// Selectable palette for tagging session tabs. Stored as hex strings (the
  /// persisted form in tab metadata); render with [fromHex].
  static const tabColors = <(String, String)>[
    ('Red', '#ef4444'),
    ('Orange', '#f97316'),
    ('Yellow', '#eab308'),
    ('Green', '#22c55e'),
    ('Teal', '#14b8a6'),
    ('Blue', '#3b82f6'),
    ('Purple', '#a855f7'),
    ('Pink', '#ec4899'),
  ];

  /// Parses a `#rrggbb` (or `#aarrggbb`) hex string into a [Color], returning
  /// [fallback] for malformed input instead of throwing during build.
  static Color fromHex(String hex, {Color fallback = textSecondary}) {
    final h = hex.replaceFirst('#', '').trim();
    if (h.length == 6) {
      final v = int.tryParse('FF$h', radix: 16);
      if (v != null) return Color(v);
    } else if (h.length == 8) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }
}

/// Consistent SnackBar styling. Callers should use these helpers rather than
/// building `SnackBar(content: Text('…'), backgroundColor: const Color(...))`
/// — the colors and durations should be tuned here once, not in every screen.
class AppSnack {
  AppSnack._();

  static void error(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  static void info(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: AppColors.textPrimary)),
      backgroundColor: AppColors.card,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.bg,
      primary: AppColors.accent,
      onPrimary: Colors.black,
      secondary: AppColors.accent,
    ),
    fontFamily: 'SF Pro Display',
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.textPrimary, fontSize: 13),
      bodySmall: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      labelMedium: TextStyle(color: AppColors.textSecondary, fontSize: 12),
    ),
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
  );
}
