import 'package:flutter/painting.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Colour aliases onto the design-system tokens ([YsColors]); kept so older
/// call sites keep their names. New code uses [YsColors] directly.
abstract final class SnippetsColors {
  static const Color bg = YsColors.background;
  static const Color sidebar = YsColors.sidebar;
  static const Color card = YsColors.card;
  static const Color cardHover = YsColors.secondary;
  static const Color border = YsColors.border;
  static const Color accent = YsColors.primary;
  static const Color textPrimary = YsColors.foreground;
  static const Color textSecondary = YsColors.mutedForeground;
  static const Color textTertiary = YsColors.mutedForeground;
  static const Color red = YsColors.error;
}
