import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Surface for `showMenu` popups, shared by the tab bar, tab and terminal
/// context menus.
const Color kYsMenuColor = YsColors.card;

/// Rounded shape for `showMenu` popups.
final ShapeBorder kYsMenuShape =
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(YsRadius.control));

/// A token-styled popup menu row: muted [icon] then [text] (foreground, or
/// mutedForeground when [muted]), with an optional [trailing] widget. A
/// disabled row ([enabled] false) is dimmed and cannot be picked; [height]
/// overrides the default row height.
PopupMenuItem<T> ysMenuItem<T>(
  T value,
  IconData icon,
  String text, {
  bool muted = false,
  bool enabled = true,
  double? height,
  Widget? trailing,
}) {
  final dim = enabled ? 1.0 : 0.45;
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: height ?? kMinInteractiveDimension,
    child: Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: YsColors.mutedForeground.withValues(alpha: dim),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: (muted ? YsColors.mutedForeground : YsColors.foreground)
                .withValues(alpha: dim),
            fontSize: 13,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    ),
  );
}
