import 'package:flutter/material.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// One plugin-contributed item in the main status bar. A tooltip is attached
/// only when the plugin supplied one.
class PluginStatusBarItem extends StatelessWidget {
  final StatusBarItem item;
  const PluginStatusBarItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final tip = item.tooltip;
    final tappable = FTappable(
      onPress: item.onClick,
      semanticsLabel: item.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(
          child: Text(
            item.label,
            style: const TextStyle(
              color: YsColors.mutedForeground,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
    if (tip == null || tip.isEmpty) return tappable;
    return Tooltip(message: tip, child: tappable);
  }
}
