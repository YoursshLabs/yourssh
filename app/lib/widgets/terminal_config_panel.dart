// app/lib/widgets/terminal_config_panel.dart
import 'package:flutter/material.dart';
import 'terminal_appearance_controls.dart';

/// Right-side workspace panel for terminal appearance settings.
/// Mirrors the snippets panel's frame (340px, dark, left border).
class TerminalConfigPanel extends StatelessWidget {
  final VoidCallback? onClose;

  const TerminalConfigPanel({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(left: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
            ),
            child: Row(
              children: [
                const Text(
                  'Terminal',
                  style: TextStyle(
                    color: Color(0xFFE5E5E5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close terminal settings',
                    onPressed: onClose,
                    icon: const Icon(Icons.close,
                        size: 16, color: Color(0xFF888888)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                TerminalAppearanceControls(
                  layout: AppearanceControlsLayout.vertical,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
