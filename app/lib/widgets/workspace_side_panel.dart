// app/lib/widgets/workspace_side_panel.dart
import 'package:flutter/material.dart';

/// Shared frame for right-side workspace panels (snippets, terminal config):
/// fixed width, dark background, left border, and a header with a title,
/// optional extra header content (e.g. a search field), and a close button.
class WorkspaceSidePanel extends StatelessWidget {
  static const double panelWidth = 340;

  final String title;
  final String closeTooltip;
  final VoidCallback? onClose;
  final Widget? headerExtra;
  final Widget child;

  const WorkspaceSidePanel({
    super.key,
    required this.title,
    required this.closeTooltip,
    required this.child,
    this.onClose,
    this.headerExtra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: panelWidth,
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
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFE5E5E5),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (onClose != null)
                      IconButton(
                        tooltip: closeTooltip,
                        onPressed: onClose,
                        icon: const Icon(Icons.close,
                            size: 16, color: Color(0xFF888888)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (headerExtra != null) ...[
                  const SizedBox(height: 8),
                  headerExtra!,
                ],
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
