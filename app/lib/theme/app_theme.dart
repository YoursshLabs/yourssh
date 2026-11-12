import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class AppColors {
  static const bg = YsColors.background;
  static const sidebar = YsColors.sidebar;
  static const card = YsColors.card;
  static const cardHover = YsColors.secondary;
  static const border = YsColors.border;
  static const accent = YsColors.primary;
  static const accentDim = Color(0xFFE87C08);
  static const textPrimary = YsColors.foreground;
  static const textSecondary = YsColors.mutedForeground;
  static const textTertiary = Color(0xFF78716C);
  static const red = YsColors.error;
  static const success = YsColors.ok;
  static const warning = YsColors.warn;
  static const offline = YsColors.off;
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
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }
}

ThemeData buildAppTheme() => ysMaterialTheme();

/// `MaterialApp.builder` for desktop: puts forui's [FTheme] and [FToaster]
/// above the Navigator so dialogs, routes and toasts all inherit them.
Widget ysRootBuilder(BuildContext context, Widget? child) =>
    _wrap(ysThemeData(), child);

/// Same as [ysRootBuilder] with touch sizing, for the mobile app.
Widget ysRootBuilderTouch(BuildContext context, Widget? child) =>
    _wrap(ysThemeDataTouch(), child);

Widget _wrap(FThemeData data, Widget? child) =>
    FTheme(data: data, child: FToaster(child: child ?? const SizedBox.shrink()));
