import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/keyword_highlight_rule.dart';
import '../providers/settings_provider.dart';
import 'terminal_appearance_controls.dart';
import 'workspace_side_panel.dart';

class TerminalConfigPanel extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onOpenSettings;

  const TerminalConfigPanel({super.key, this.onClose, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return WorkspaceSidePanel(
      title: 'Terminal',
      closeTooltip: 'Close terminal settings',
      onClose: onClose,
      child: ListView(
        padding: const EdgeInsets.all(YsSpace.s4),
        children: [
          const TerminalAppearanceControls(
            layout: AppearanceControlsLayout.vertical,
          ),
          const SizedBox(height: YsSpace.s5),
          _KeywordHighlightCompact(onOpenSettings: onOpenSettings),
        ],
      ),
    );
  }
}

class _KeywordHighlightCompact extends StatelessWidget {
  final VoidCallback? onOpenSettings;
  const _KeywordHighlightCompact({this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final rules = settings.keywordHighlightRules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KEYWORD HIGHLIGHTING',
          style: TextStyle(
            color: YsColors.mutedForeground,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: YsSpace.s2),
        FTileGroup(
          children: [
            FTile.raw(
              child: FSwitch(
                key: const Key('keyword-highlight-enable'),
                value: settings.keywordHighlightingEnabled,
                onChange: (v) => context
                    .read<SettingsProvider>()
                    .save(keywordHighlightingEnabled: v),
                label: const Text('Enable'),
              ),
            ),
            for (final (i, rule) in rules.indexed)
              FTile.raw(
                child: FSwitch(
                  key: ValueKey('keyword-rule-$i'),
                  value: rule.enabled,
                  onChange: (v) {
                    final updated =
                        List<AppKeywordHighlightRule>.from(rules);
                    updated[i] = rule.copyWith(enabled: v);
                    context
                        .read<SettingsProvider>()
                        .save(keywordHighlightRules: updated);
                  },
                  label: Row(
                    children: [
                      if (rule.background != null) _Dot(color: rule.background!),
                      if (rule.foreground != null) ...[
                        if (rule.background != null) const SizedBox(width: 4),
                        _Dot(color: rule.foreground!, border: true),
                      ],
                      const SizedBox(width: YsSpace.s2),
                      Expanded(
                        child: Text(rule.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (onOpenSettings != null) ...[
          const SizedBox(height: YsSpace.s2),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              variant: .ghost,
              size: .sm,
              mainAxisSize: MainAxisSize.min,
              onPress: onOpenSettings,
              child: const Text('Manage rules in Settings →'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final bool border;
  const _Dot({required this.color, this.border = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border
            ? Border.all(color: YsColors.mutedForeground, width: 1)
            : null,
      ),
    );
  }
}
