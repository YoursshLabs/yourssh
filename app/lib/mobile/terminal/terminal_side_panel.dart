import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../providers/command_history_provider.dart';
import '../../widgets/terminal_appearance_controls.dart';
import '../theme/mobile_tokens.dart';

/// Termius-style terminal side panel as a bottom sheet: Keys (extended
/// keyboard), Snippets, Command History, and Themes. Insertions/keys are
/// routed back to the active session via the callbacks.
Future<void> showTerminalSidePanel(
  BuildContext context, {
  required String sessionId,
  required void Function(String text) onInsert,
  required void Function(TerminalKey key, {bool ctrl, bool alt}) onKey,
  int initialTab = 0,
}) {
  return showFSheet<void>(
    context: context,
    side: .btt,
    mainAxisMaxRatio: 0.6,
    builder: (_) => _SidePanel(
      sessionId: sessionId,
      onInsert: onInsert,
      onKey: onKey,
      initialTab: initialTab,
    ),
  );
}

class _SidePanel extends StatelessWidget {
  final String sessionId;
  final void Function(String text) onInsert;
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final int initialTab;

  const _SidePanel({
    required this.sessionId,
    required this.onInsert,
    required this.onKey,
    required this.initialTab,
  });

  @override
  Widget build(BuildContext context) {
    // Fixed 60 % height so FTabs can expand its content.
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: FTabs(
          expands: true,
          control: .managed(initial: initialTab),
          children: [
            FTabEntry(
              label: const Text('Keys'),
              child: _KeysGrid(
                  onKey: onKey, onClose: () => Navigator.pop(context)),
            ),
            FTabEntry(
              label: const Text('Snippets'),
              child: _SnippetsTab(onInsert: (c) {
                onInsert(c);
                Navigator.pop(context);
              }),
            ),
            FTabEntry(
              label: const Text('History'),
              child: _HistoryTab(
                  sessionId: sessionId,
                  onInsert: (c) {
                    onInsert(c);
                    Navigator.pop(context);
                  }),
            ),
            const FTabEntry(
              label: Text('Themes'),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(MobileTokens.space4),
                child: TerminalAppearanceControls(
                    layout: AppearanceControlsLayout.rows),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeysGrid extends StatelessWidget {
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final VoidCallback onClose;
  const _KeysGrid({required this.onKey, required this.onClose});

  // All TerminalKey members verified present in packages/xterm/lib/src/core/input/keys.dart:
  // home (line 255), end (line 264), pageUp (line 258), pageDown (line 267),
  // f1 (line 207) ... f10 (line 234) — all confirmed.
  static const _keys = <(String, TerminalKey)>[
    ('Esc', TerminalKey.escape),
    ('Tab', TerminalKey.tab),
    ('Home', TerminalKey.home),
    ('End', TerminalKey.end),
    ('PgUp', TerminalKey.pageUp),
    ('PgDn', TerminalKey.pageDown),
    ('↑', TerminalKey.arrowUp),
    ('↓', TerminalKey.arrowDown),
    ('←', TerminalKey.arrowLeft),
    ('→', TerminalKey.arrowRight),
    ('F1', TerminalKey.f1),
    ('F2', TerminalKey.f2),
    ('F3', TerminalKey.f3),
    ('F4', TerminalKey.f4),
    ('F5', TerminalKey.f5),
    ('F6', TerminalKey.f6),
    ('F7', TerminalKey.f7),
    ('F8', TerminalKey.f8),
    ('F9', TerminalKey.f9),
    ('F10', TerminalKey.f10),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView(
      padding: const EdgeInsets.all(MobileTokens.space3),
      // Fixed row height: the 44 px touch target is a floor, not a ratio.
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: MobileTokens.space2,
        crossAxisSpacing: MobileTokens.space2,
        mainAxisExtent: MobileTokens.touchTarget,
      ),
      children: [
        for (final (label, key) in _keys)
          FButton(
            size: .sm,
            variant: .outline,
            onPress: () => onKey(key),
            child: Flexible(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
            ),
          ),
      ],
    );
  }
}

class _SnippetsTab extends StatefulWidget {
  final void Function(String command) onInsert;
  const _SnippetsTab({required this.onInsert});

  @override
  State<_SnippetsTab> createState() => _SnippetsTabState();
}

class _SnippetsTabState extends State<_SnippetsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<SnippetProvider>().snippets;
    final shown = filterSnippets(all, _query);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MobileTokens.space3),
          child: FTextField(
            control: .managed(onChange: (v) => setState(() => _query = v.text)),
            hint: 'Search snippets',
            prefixBuilder: (context, style, variants) =>
                FTextField.prefixIconBuilder(
                    context, style, variants, const Icon(FLucideIcons.search)),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: Text('No snippets',
                      style: TextStyle(color: YsColors.mutedForeground)))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final s = shown[i];
                    return FItem(
                      title: Text(s.label),
                      subtitle: Text(s.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontFamily: 'monospace')),
                      onPress: () => widget.onInsert(s.command),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String sessionId;
  final void Function(String command) onInsert;
  const _HistoryTab({required this.sessionId, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final entries =
        context.watch<CommandHistoryProvider>().historyFor(sessionId).entries;
    if (entries.isEmpty) {
      return const Center(
          child: Text('No command history yet',
              style: TextStyle(color: YsColors.mutedForeground)));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final cmd = entries[i]; // entries is already newest-first (addFirst)
        return FItem(
          title: Text(cmd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          onPress: () => onInsert(cmd),
        );
      },
    );
  }
}
