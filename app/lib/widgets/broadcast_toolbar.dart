// app/lib/widgets/broadcast_toolbar.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../providers/plugin_provider.dart';
import '../providers/terminal_layout_provider.dart';

class BroadcastToolbar extends StatelessWidget {
  const BroadcastToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TerminalLayoutProvider>();
    final snippetsEnabled = context
        .watch<PluginProvider>()
        .isEnabled(YourSSHSnippetsPlugin.pluginId);

    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text('Layout:', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
          const SizedBox(width: 8),
          _LayoutButton(
            icon: Icons.crop_square,
            tooltip: 'Single',
            selected: layout.layout == SplitLayout.single,
            onTap: () => layout.setLayout(SplitLayout.single),
          ),
          _LayoutButton(
            icon: Icons.view_column,
            tooltip: 'Split Horizontal',
            selected: layout.layout == SplitLayout.horizontal,
            onTap: () => layout.setLayout(SplitLayout.horizontal),
          ),
          _LayoutButton(
            icon: Icons.table_rows,
            tooltip: 'Split Vertical',
            selected: layout.layout == SplitLayout.vertical,
            onTap: () => layout.setLayout(SplitLayout.vertical),
          ),
          _LayoutButton(
            icon: Icons.grid_view,
            tooltip: 'Quad',
            selected: layout.layout == SplitLayout.quad,
            onTap: () => layout.setLayout(SplitLayout.quad),
          ),
          const SizedBox(width: 8),
          if (snippetsEnabled)
            _LayoutButton(
              icon: Icons.code,
              tooltip: 'Toggle Snippets Panel',
              selected: layout.snippetsPanelVisible,
              onTap: layout.toggleSnippetsPanel,
            ),
          _LayoutButton(
            icon: Icons.tune,
            tooltip: 'Toggle Terminal Settings',
            selected: layout.configPanelVisible,
            onTap: () => layout.toggleSidePanel(SidePanel.terminalConfig),
          ),
          const Spacer(),
          if (layout.paneCount > 1)
            InkWell(
              onTap: layout.toggleBroadcast,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: layout.broadcastEnabled
                      ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: Border.all(
                    color: layout.broadcastEnabled
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF2A2A2A),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cell_tower,
                      size: 14,
                      color: layout.broadcastEnabled
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF888888),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Broadcast',
                      style: TextStyle(
                        fontSize: 12,
                        color: layout.broadcastEnabled
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LayoutButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: selected ? const Color(0xFF22C55E) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}
