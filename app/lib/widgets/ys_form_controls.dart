import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

// Form controls shared by Settings and the non-settings panels (containers,
// Kubernetes, audit, port forwarding, ...). `settings/settings_tiles.dart`
// re-exports this file, so Settings code needs no extra import.

/// [FTileGroup] for settings tiles. Slide-to-press between tiles is off
/// app-wide in `ysThemeData()` (ruling P16: the group's [FTappableGroup]
/// swallowed taps on buttons inside a text field's suffix, such as a
/// password reveal toggle), so this is a plain alias.
FTileGroup settingsTileGroup({required List<FTileMixin> children}) =>
    FTileGroup(children: children);

/// Width of a select in a settings row.
const kSettingsSelectWidth = 200.0;

/// [FSelect] over a fixed list of `(value, text)` options. The select's own
/// value is the option index, so duplicate texts stay distinct and a value
/// that is not among the options shows the hint instead of asserting.
class SettingsSelect<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double width;
  final String? hint;

  const SettingsSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.width = kSettingsSelectWidth,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.$1 == value);
    return SizedBox(
      width: width,
      child: FSelect<int>.rich(
        size: .sm,
        control: .lifted(
          value: index < 0 ? null : index,
          onChange: (i) {
            if (i != null) onChanged(options[i].$1);
          },
        ),
        format: (i) => options[i].$2,
        hint: hint,
        children: [
          for (final (i, (_, text)) in options.indexed)
            FSelectItem<int>(title: Text(text), value: i),
        ],
      ),
    );
  }
}

/// Icon-only ghost button with a tooltip (the tooltip doubles as the
/// semantics label).
class SettingsIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;

  const SettingsIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: FButton.icon(
      variant: .ghost,
      size: .xs,
      semanticsLabel: tooltip,
      onPress: onPress,
      child: Icon(icon),
    ),
  );
}

/// Muted caption above a group of fields inside a content tile.
class SettingsCaption extends StatelessWidget {
  final String text;
  const SettingsCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: YsColors.mutedForeground, fontSize: 12),
  );
}
