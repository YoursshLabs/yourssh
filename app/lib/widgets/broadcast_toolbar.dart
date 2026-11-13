// app/lib/widgets/broadcast_toolbar.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../providers/plugin_provider.dart';
import '../providers/terminal_layout_provider.dart';

/// Workspace header: [leading] (host chips) on the left, layout / panel
/// toggles and Broadcast on the right, then [trailing] (the main screen's
/// network stats, Share and AI controls) at the right edge. The action
/// cluster scrolls instead of overflowing when the workspace is narrow (side
/// panel open).
class BroadcastToolbar extends StatelessWidget {
  final Widget? leading;
  final Widget? trailing;
  const BroadcastToolbar({super.key, this.leading, this.trailing});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TerminalLayoutProvider>();
    final snippetsEnabled = context
        .watch<PluginProvider>()
        .isEnabled(YourSSHSnippetsPlugin.pluginId);

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LayoutButton(
          icon: FLucideIcons.square,
          tooltip: 'Single',
          selected: layout.layout == SplitLayout.single,
          onTap: () => layout.setLayout(SplitLayout.single),
        ),
        _LayoutButton(
          icon: FLucideIcons.columns2,
          tooltip: 'Split Horizontal',
          selected: layout.layout == SplitLayout.horizontal,
          onTap: () => layout.setLayout(SplitLayout.horizontal),
        ),
        _LayoutButton(
          icon: FLucideIcons.rows2,
          tooltip: 'Split Vertical',
          selected: layout.layout == SplitLayout.vertical,
          onTap: () => layout.setLayout(SplitLayout.vertical),
        ),
        _LayoutButton(
          icon: FLucideIcons.layoutGrid,
          tooltip: 'Quad',
          selected: layout.layout == SplitLayout.quad,
          onTap: () => layout.setLayout(SplitLayout.quad),
        ),
        const SizedBox(width: YsSpace.s2),
        if (snippetsEnabled)
          _LayoutButton(
            icon: FLucideIcons.code,
            tooltip: 'Toggle Snippets Panel',
            selected: layout.snippetsPanelVisible,
            onTap: layout.toggleSnippetsPanel,
          ),
        _LayoutButton(
          icon: FLucideIcons.slidersHorizontal,
          tooltip: 'Toggle Terminal Settings',
          selected: layout.configPanelVisible,
          onTap: () => layout.toggleSidePanel(SidePanel.terminalConfig),
        ),
        if (layout.paneCount > 1) ...[
          const SizedBox(width: YsSpace.s2),
          FButton(
            variant: layout.broadcastEnabled ? .secondary : .outline,
            size: .sm,
            mainAxisSize: MainAxisSize.min,
            onPress: layout.toggleBroadcast,
            prefix: Icon(
              FLucideIcons.radioTower,
              color: layout.broadcastEnabled
                  ? YsColors.accentText
                  : YsColors.mutedForeground,
            ),
            child: const Text('Broadcast'),
          ),
        ],
      ],
    );

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: YsColors.card,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
      // Chips take the left, the actions hug the right edge (before
      // [trailing]). The actions keep their natural width up to 60% of the
      // bar and scroll beyond that, so a narrow window never overflows.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(child: leading ?? const SizedBox.shrink()),
            const SizedBox(width: YsSpace.s2),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.6,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: actions,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: YsSpace.s2),
              trailing!,
            ],
          ],
        ),
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
      child: FButton.icon(
        variant: selected ? .secondary : .ghost,
        size: .sm,
        selected: selected,
        onPress: onTap,
        child: Icon(
          icon,
          color: selected ? YsColors.accentText : YsColors.mutedForeground,
        ),
      ),
    );
  }
}
