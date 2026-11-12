import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Focus nodes for the tiles of [switchRowTile], one per switch key. A tile
/// is built by a plain function (there is no State to own a node), and the
/// keys are a small fixed set of constants, so the nodes are kept for the app
/// lifetime. They never take focus: the switch inside is the row's only
/// focus stop.
final Map<Key, FocusNode> _tileFocusNodes = {};

/// A switch row: label (+ description) and an [FSwitch] inside an
/// [FTile.raw]. A press anywhere on the row toggles the switch (the tile's
/// `onPress`); a press on the switch itself toggles it once, because the
/// switch's own recognizer wins over the tile's.
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
