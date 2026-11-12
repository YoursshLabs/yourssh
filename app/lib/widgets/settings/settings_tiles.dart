import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../switch_row_tile.dart';

/// One Settings section: a title above its content, which is usually an
/// [FTileGroup] built from [tiles].
class SettingsSection extends StatelessWidget {
  final String title;
  final List<FTileMixin>? tiles;
  final Widget? child;

  const SettingsSection({
    super.key,
    required this.title,
    this.tiles,
    this.child,
  }) : assert((tiles == null) != (child == null), 'pass tiles or child');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      YsSectionHeader(title: title),
      child ?? settingsTileGroup(children: tiles!),
    ],
  );
}

/// [FTileGroup] for settings tiles. Slide-to-press between tiles is off
/// app-wide in `ysThemeData()` (ruling P16: the group's [FTappableGroup]
/// swallowed taps on buttons inside a text field's suffix, such as a
/// password reveal toggle), so this is a plain alias.
FTileGroup settingsTileGroup({required List<FTileMixin> children}) =>
    FTileGroup(children: children);

/// A card that looks like an [FTileGroup] for content that lays out its own
/// rows (the shared terminal appearance controls, the sync forms).
class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SettingsCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colors.card,
        shape: RoundedSuperellipseBorder(
          side: BorderSide(
            color: theme.colors.border,
            width: theme.style.borderWidth,
          ),
          borderRadius: theme.style.borderRadius.md,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Label (+ optional description) on the left, [trailing] on the right.
/// Text wraps; [trailing] keeps its own width, so give a select or text
/// field a fixed width.
class SettingsRow extends StatelessWidget {
  final String label;
  final String? description;
  final Widget? descriptionWidget;
  final Widget? trailing;

  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    this.descriptionWidget,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final field = context.theme.style.formFieldStyle;
    const none = <FVariant>{};
    final desc =
        descriptionWidget ?? (description == null ? null : Text(description!));
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle(
                style: field.labelTextStyle.resolve(none),
                child: Text(label),
              ),
              if (desc != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: DefaultTextStyle(
                    style: field.descriptionTextStyle.resolve(none),
                    child: desc,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: YsSpace.s3), trailing!],
      ],
    );
  }
}

/// A row tile: [SettingsRow] inside an [FTile.raw].
FTile settingsRowTile({
  Key? key,
  required String label,
  String? description,
  Widget? descriptionWidget,
  Widget? trailing,
}) => FTile.raw(
  key: key,
  child: SettingsRow(
    label: label,
    description: description,
    descriptionWidget: descriptionWidget,
    trailing: trailing,
  ),
);

/// A switch tile: label and description left, switch right. A press
/// anywhere on the row toggles it; the switch is the single focus stop.
FTile settingsSwitchTile({
  required Key key,
  required String label,
  String? description,
  required bool value,
  required ValueChanged<bool> onChange,
}) => switchRowTile(
  key: key,
  leadingLabel: true,
  label: Text(label),
  description: description == null ? null : Text(description),
  value: value,
  onChange: onChange,
);

/// A tile holding free-form content (a form, a list of buttons).
FTile settingsContentTile({Key? key, required Widget child}) =>
    FTile.raw(key: key, child: child);

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

/// Text that ellipsizes inside a button squeezed by a narrow window.
Widget settingsButtonText(String text) =>
    Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis));

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
