import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'workspace_side_panel.dart';

class TerminalSnippetsPanel extends StatefulWidget {
  final bool canRun;
  final ValueChanged<Snippet> onRunSnippet;
  final VoidCallback? onClose;

  const TerminalSnippetsPanel({
    super.key,
    required this.canRun,
    required this.onRunSnippet,
    this.onClose,
  });

  @override
  State<TerminalSnippetsPanel> createState() => _TerminalSnippetsPanelState();
}

class _TerminalSnippetsPanelState extends State<TerminalSnippetsPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final filtered = filterSnippets(snippets, _query);

    // Group by tag. Groups appear in first-seen order (the provider's order),
    // untagged snippets last; the provider's order is kept inside a group.
    final groups = <String, List<Snippet>>{};
    for (final s in filtered) {
      groups.putIfAbsent(s.tag, () => []).add(s);
    }
    final tags = [
      ...groups.keys.where((t) => t.isNotEmpty),
      if (groups.containsKey('')) '',
    ];

    return WorkspaceSidePanel(
      title: 'Snippets',
      closeTooltip: 'Close snippets panel',
      onClose: widget.onClose,
      headerExtra: FTextField(
        key: const Key('snippets-search'),
        control: FTextFieldControl.managed(
          onChange: (v) => setState(() => _query = v.text),
        ),
        size: .sm,
        hint: 'Search snippets…',
        prefixBuilder: (context, style, variants) =>
            FTextField.prefixIconBuilder(
                context, style, variants, const Icon(FLucideIcons.search)),
      ),
      child: Column(
        children: [
          if (!widget.canRun)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  YsSpace.s3, YsSpace.s3, YsSpace.s3, 0),
              child: FAlert(
                variant: .destructive,
                title: const Text('No active SSH pane selected'),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? YsEmptyState(
                    icon: FLucideIcons.code,
                    title: _query.isEmpty
                        ? 'No snippets yet'
                        : 'No snippets match "$_query"',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(YsSpace.s3),
                    itemCount: tags.length,
                    itemBuilder: (context, i) {
                      final tag = tags[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tag.isNotEmpty) YsSectionHeader(title: tag),
                          FTileGroup(
                            children: [
                              for (final snippet in groups[tag]!)
                                _snippetTile(
                                  snippet,
                                  canRun: widget.canRun,
                                  onRun: () => widget.onRunSnippet(snippet),
                                ),
                            ],
                          ),
                          const SizedBox(height: YsSpace.s3),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

FTile _snippetTile(
  Snippet snippet, {
  required bool canRun,
  required VoidCallback onRun,
}) {
  return FTile(
    key: ValueKey('snippet-${snippet.id}'),
    title: Text(snippet.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          snippet.command,
          style: const TextStyle(
            color: YsColors.accentText,
            fontSize: 12,
            fontFamily: kYsMonoFontFamily,
            fontFamilyFallback: kYsMonoFontFallback,
          ),
        ),
        if (snippet.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.s1),
            child: Text(
              snippet.description,
              style: const TextStyle(
                  color: YsColors.mutedForeground, fontSize: 11),
            ),
          ),
        const SizedBox(height: YsSpace.s2),
        Wrap(
          spacing: YsSpace.s2,
          children: [
            Tooltip(
              message: 'Run snippet',
              child: FButton(
                variant: .ghost,
                size: .sm,
                mainAxisSize: MainAxisSize.min,
                onPress: canRun ? onRun : null,
                prefix: const Icon(FLucideIcons.play),
                child: const Text('Run'),
              ),
            ),
            Tooltip(
              message: 'Copy snippet',
              child: FButton(
                variant: .ghost,
                size: .sm,
                mainAxisSize: MainAxisSize.min,
                onPress: () =>
                    Clipboard.setData(ClipboardData(text: snippet.command)),
                prefix: const Icon(FLucideIcons.copy),
                child: const Text('Copy'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
