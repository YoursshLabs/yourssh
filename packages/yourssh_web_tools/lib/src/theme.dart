import 'package:flutter/painting.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Colour aliases onto the design-system tokens ([YsColors]); kept so
/// not-yet-migrated screens keep compiling. New code uses [YsColors] directly.
abstract final class WebToolsColors {
  static const Color bg = YsColors.background;
  static const Color sidebar = YsColors.sidebar;
  static const Color card = YsColors.card;
  static const Color cardHover = YsColors.secondary;
  static const Color border = YsColors.border;
  static const Color accent = YsColors.primary;
  static const Color accentDim = YsColors.primary;
  static const Color textPrimary = YsColors.foreground;
  static const Color textSecondary = YsColors.mutedForeground;
  static const Color textTertiary = YsColors.mutedForeground;
  static const Color red = YsColors.error;
  static const Color orange = YsColors.warn;
  static const Color blue = YsColors.accentText;
}
