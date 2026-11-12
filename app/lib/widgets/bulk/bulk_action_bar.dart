import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Replaces the hosts-dashboard top bar while selection mode is active.
class BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onConnectAll;
  final VoidCallback onRunCommand;
  final VoidCallback onPushFiles;
  final VoidCallback onDone;

  const BulkActionBar({
    super.key,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onClear,
    required this.onConnectAll,
    required this.onRunCommand,
    required this.onPushFiles,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s5),
      child: Row(
        children: [
          Text(
            '$selectedCount selected',
            style: const TextStyle(
              color: YsColors.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: YsSpace.s4),
          _BarBtn(label: 'Select all', onPress: onSelectAll),
          const SizedBox(width: YsSpace.s2),
          _BarBtn(label: 'Clear', onPress: hasSelection ? onClear : null),
          Expanded(
            // reverse anchors the action cluster to the right edge; when the
            // bar is too narrow it scrolls with Done still visible.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BarBtn(
                    icon: FLucideIcons.cable,
                    label: 'Connect all',
                    onPress: hasSelection ? onConnectAll : null,
                  ),
                  const SizedBox(width: YsSpace.s2),
                  _BarBtn(
                    icon: FLucideIcons.squareTerminal,
                    label: 'Run command',
                    onPress: hasSelection ? onRunCommand : null,
                  ),
                  const SizedBox(width: YsSpace.s2),
                  _BarBtn(
                    icon: FLucideIcons.upload,
                    label: 'Push files',
                    onPress: hasSelection ? onPushFiles : null,
                  ),
                  const SizedBox(width: YsSpace.s4),
                  _BarBtn(label: 'Done', onPress: onDone, primary: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One bar button; a null [onPress] disables it.
class _BarBtn extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onPress;
  final bool primary;
  const _BarBtn({
    this.icon,
    required this.label,
    required this.onPress,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => FButton(
    variant: primary ? .primary : .outline,
    size: .sm,
    mainAxisSize: MainAxisSize.min,
    onPress: onPress,
    prefix: icon == null ? null : Icon(icon),
    child: Text(label),
  );
}
