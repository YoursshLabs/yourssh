import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Surface for `showMenu` popups, shared by the tab bar and tab context menus.
const Color kYsMenuColor = YsColors.card;

/// Rounded shape for `showMenu` popups.
final ShapeBorder kYsMenuShape =
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(YsRadius.control));

/// A token-styled popup menu row: muted [icon] then [text] (foreground, or
/// mutedForeground when [muted]), with an optional [trailing] widget.
PopupMenuItem<String> ysMenuItem(
  String value,
  IconData icon,
  String text, {
  bool muted = false,
  Widget? trailing,
}) => PopupMenuItem<String>(
  value: value,
  child: Row(
    children: [
      Icon(icon, size: 14, color: YsColors.mutedForeground),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          color: muted ? YsColors.mutedForeground : YsColors.foreground,
          fontSize: 13,
        ),
      ),
      if (trailing != null) ...[const Spacer(), trailing],
    ],
  ),
);
