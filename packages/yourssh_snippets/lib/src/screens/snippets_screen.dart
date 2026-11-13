// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/snippet.dart';
import '../providers/snippet_provider.dart';

class SnippetsScreen extends StatefulWidget {
  final YourSSHPluginContext pluginContext;

  const SnippetsScreen({super.key, required this.pluginContext});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  String _search = '';
  bool _showPanel = false;

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final filtered = filterSnippets(snippets, _search);

    return ColoredBox(
      color: YsColors.background,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  onSearch: (v) => setState(() => _search = v),
                  onAdd: () => setState(() => _showPanel = true),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const YsEmptyState(
                          icon: FLucideIcons.squareTerminal,
                          title: 'No snippets',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(YsSpace.s5),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _SnippetTile(
                            key: ValueKey('snippet-${filtered[i].id}'),
                            snippet: filtered[i],
                            pluginContext: widget.pluginContext,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (_showPanel)
            _SnippetPanel(
              onClose: () => setState(() => _showPanel = false),
              onSave: (snippet) async {
                await context.read<SnippetProvider>().add(snippet);
                if (mounted) setState(() => _showPanel = false);
              },
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ValueChanged<String> onSearch;
  final VoidCallback onAdd;
  const _TopBar({required this.onSearch, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s5),
      child: Row(
        children: [
          Expanded(
            child: FTextField(
              key: const ValueKey('snippet-search'),
              control: .managed(onChange: (v) => onSearch(v.text)),
              size: .sm,
              hint: 'Search snippets…',
              autocorrect: false,
              enableSuggestions: false,
              prefixBuilder: (context, style, variants) => const Padding(
                padding: EdgeInsets.only(left: YsSpace.s3),
                child: Icon(FLucideIcons.search, size: 16),
              ),
            ),
          ),
          const SizedBox(width: YsSpace.s3),
          IntrinsicWidth(
            child: FButton(
              size: .sm,
              mainAxisSize: .min,
              prefix: const Icon(FLucideIcons.plus),
              onPress: onAdd,
              child: const Text('NEW SNIPPET'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnippetTile extends StatefulWidget {
  final Snippet snippet;
  final YourSSHPluginContext pluginContext;

  const _SnippetTile({
    super.key,
    required this.snippet,
    required this.pluginContext,
  });

  @override
  State<_SnippetTile> createState() => _SnippetTileState();
}

class _SnippetTileState extends State<_SnippetTile> {
  bool _hovered = false;
  bool _focused = false;

  Future<void> _runSnippet() async {
    final session = widget.pluginContext.activeSession;
    if (session == null || !session.isConnected) {
      if (!mounted) return;
      showYsToast(context, 'No active SSH session to run this snippet');
      return;
    }

    try {
      await widget.pluginContext.sendInput(
        session.sessionId,
        '${widget.snippet.command}\n',
      );
      if (!mounted) return;
      showYsToast(context, 'Sent "${widget.snippet.label}" to terminal');
    } catch (e) {
      if (!mounted) return;
      showYsToast(
        context,
        'Failed to run snippet: $e',
        kind: YsToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snippet;
    // Row actions show on hover and while any of them holds keyboard focus,
    // so they stay reachable without a mouse.
    final showActions = _hovered || _focused;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          margin: const EdgeInsets.only(bottom: YsSpace.s2),
          padding: const EdgeInsets.symmetric(
            horizontal: YsSpace.s4,
            vertical: YsSpace.s3,
          ),
          decoration: BoxDecoration(
            color: showActions ? YsColors.secondary : YsColors.card,
            borderRadius: BorderRadius.circular(YsRadius.card),
            border: Border.all(color: YsColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YsColors.foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (s.tag.isNotEmpty) ...[
                          const SizedBox(width: YsSpace.s2),
                          Flexible(child: YsTag(s.tag)),
                        ],
                      ],
                    ),
                    const SizedBox(height: YsSpace.s1),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: YsSpace.s2,
                        vertical: YsSpace.s1,
                      ),
                      decoration: BoxDecoration(
                        color: YsColors.background,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        s.command,
                        style: const TextStyle(
                          color: YsColors.accentText,
                          fontSize: 12,
                          fontFamily: kYsMonoFontFamily,
                          fontFamilyFallback: kYsMonoFontFallback,
                        ),
                      ),
                    ),
                    if (s.description.isNotEmpty) ...[
                      const SizedBox(height: YsSpace.s1),
                      Text(
                        s.description,
                        style: const TextStyle(
                          color: YsColors.mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Always built (so Tab reaches them); only painted on hover/focus.
              Opacity(
                opacity: showActions ? 1 : 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionBtn(
                      icon: FLucideIcons.play,
                      tooltip: 'Run in terminal',
                      color: YsColors.primary,
                      onTap: () {
                        _runSnippet();
                      },
                    ),
                    const SizedBox(width: YsSpace.s1),
                    _ActionBtn(
                      icon: FLucideIcons.copy,
                      tooltip: 'Copy',
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: s.command)),
                    ),
                    const SizedBox(width: YsSpace.s1),
                    _ActionBtn(
                      icon: FLucideIcons.trash2,
                      tooltip: 'Delete',
                      color: YsColors.error,
                      onTap: () => context.read<SnippetProvider>().delete(s.id),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: FButton.icon(
        variant: .outline,
        size: .xs,
        semanticsLabel: tooltip,
        onPress: onTap,
        child: Icon(icon, color: color),
      ),
    );
  }
}

// ── Snippet Panel ─────────────────────────────────────────

class _SnippetPanel extends StatefulWidget {
  final VoidCallback onClose;
  final Future<void> Function(Snippet) onSave;
  const _SnippetPanel({required this.onClose, required this.onSave});

  @override
  State<_SnippetPanel> createState() => _SnippetPanelState();
}

class _SnippetPanelState extends State<_SnippetPanel> {
  final _label = TextEditingController();
  final _command = TextEditingController();
  final _description = TextEditingController();
  final _tag = TextEditingController();
  bool _saving = false;
  bool _labelMissing = false;
  bool _commandMissing = false;

  @override
  void dispose() {
    for (final c in [_label, _command, _description, _tag]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    // Same rule as before: the raw (untrimmed) value must not be empty.
    final labelMissing = _label.text.isEmpty;
    final commandMissing = _command.text.isEmpty;
    setState(() {
      _labelMissing = labelMissing;
      _commandMissing = commandMissing;
    });
    if (labelMissing || commandMissing) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        Snippet(
          label: _label.text.trim(),
          command: _command.text.trim(),
          description: _description.text.trim(),
          tag: _tag.text.trim(),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(left: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                YsSpace.s4,
                YsSpace.s4,
                YsSpace.s4,
                YsSpace.s5,
              ),
              children: [
                FTextField(
                  key: const ValueKey('snippet-label'),
                  control: .managed(
                    controller: _label,
                    onChange: (_) {
                      if (_labelMissing) setState(() => _labelMissing = false);
                    },
                  ),
                  label: const Text('Label'),
                  autofocus: true,
                  error: _labelMissing ? const Text('Required') : null,
                ),
                const SizedBox(height: YsSpace.s3),
                FTextField.multiline(
                  key: const ValueKey('snippet-command'),
                  control: .managed(
                    controller: _command,
                    onChange: (_) {
                      if (_commandMissing) {
                        setState(() => _commandMissing = false);
                      }
                    },
                  ),
                  label: const Text('Command'),
                  minLines: 3,
                  maxLines: 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  error: _commandMissing ? const Text('Required') : null,
                ),
                const SizedBox(height: YsSpace.s3),
                FTextField(
                  key: const ValueKey('snippet-description'),
                  control: .managed(controller: _description),
                  label: const Text('Description (optional)'),
                ),
                const SizedBox(height: YsSpace.s3),
                FTextField(
                  key: const ValueKey('snippet-tag'),
                  control: .managed(controller: _tag),
                  label: const Text('Tag (optional)'),
                ),
                const SizedBox(height: YsSpace.s5),
                FButton(
                  onPress: _saving ? null : _submit,
                  prefix: _saving ? const FCircularProgress(size: .sm) : null,
                  child: const Text('Add Snippet'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'New Snippet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: YsColors.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Tooltip(
            message: 'Close',
            excludeFromSemantics: true,
            child: FButton.icon(
              variant: .outline,
              size: .xs,
              semanticsLabel: 'Close',
              onPress: widget.onClose,
              child: const Icon(FLucideIcons.x),
            ),
          ),
        ],
      ),
    );
  }
}
