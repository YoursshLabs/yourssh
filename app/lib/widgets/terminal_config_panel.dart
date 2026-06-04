// app/lib/widgets/terminal_config_panel.dart
import 'package:flutter/material.dart';
import 'terminal_appearance_controls.dart';
import 'workspace_side_panel.dart';

/// Right-side workspace panel for terminal appearance settings.
class TerminalConfigPanel extends StatelessWidget {
  final VoidCallback? onClose;

  const TerminalConfigPanel({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    return WorkspaceSidePanel(
      title: 'Terminal',
      closeTooltip: 'Close terminal settings',
      onClose: onClose,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          TerminalAppearanceControls(
            layout: AppearanceControlsLayout.vertical,
          ),
        ],
      ),
    );
  }
}
