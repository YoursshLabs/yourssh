import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Focus nodes for the tiles of [switchRowTile], one per switch key. A tile
/// is built by a plain function (there is no State to own a node), and the
/// entries are bounded by the number of installed plugins and settings
/// switches, and are never disposed. They never take focus: the switch inside is the row's only
/// focus stop.
final Map<Key, FocusNode> _tileFocusNodes = {};

/// A switch row: label (+ description) and an [FSwitch] inside an
/// [FTile.raw]. A press anywhere on the row toggles the switch (the tile's
/// `onPress`); a press on the switch itself toggles it once, because the
/// switch's own recognizer wins over the tile's.
///
/// The `key` must be unique among simultaneously mounted tiles: it keys the
/// tile's shared [FocusNode], so two live tiles with the same key would share
/// one focus node.
FTile switchRowTile({
  required Key key,
  required Widget label,
  Widget? description,
  required bool value,
  required ValueChanged<bool> onChange,
  bool leadingLabel = false,
}) => FTile.raw(
  focusNode: _tileFocusNodes.putIfAbsent(
    key,
    () => FocusNode(
      debugLabel: 'switch row tile',
      canRequestFocus: false,
      skipTraversal: true,
    ),
  ),
  onPress: () => onChange(!value),
  child: FSwitch(
    key: key,
    leadingLabel: leadingLabel,
    label: label,
    description: description,
    value: value,
    onChange: onChange,
  ),
);
