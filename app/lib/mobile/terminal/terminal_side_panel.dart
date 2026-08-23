import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../providers/command_history_provider.dart';
import '../../theme/app_theme.dart';
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
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(MobileTokens.radiusCard)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.6,
      child: _SidePanel(
        sessionId: sessionId,
        onInsert: onInsert,
        onKey: onKey,
        initialTab: initialTab,
      ),
    ),
  );
}

class _SidePanel extends StatefulWidget {
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
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(text: 'Keys'),
              Tab(text: 'Snippets'),
              Tab(text: 'History'),
              Tab(text: 'Themes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _KeysGrid(onKey: widget.onKey, onClose: () => Navigator.pop(context)),
                _SnippetsTab(onInsert: (c) {
                  widget.onInsert(c);
                  Navigator.pop(context);
                }),
                _HistoryTab(sessionId: widget.sessionId, onInsert: (c) {
                  widget.onInsert(c);
                  Navigator.pop(context);
                }),
                const SingleChildScrollView(
                  padding: EdgeInsets.all(MobileTokens.space4),
                  child: TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ),
              ],
            ),
          ),
        ],
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
    return GridView.count(
      crossAxisCount: 5,
      padding: const EdgeInsets.all(MobileTokens.space3),
      mainAxisSpacing: MobileTokens.space2,
      crossAxisSpacing: MobileTokens.space2,
      childAspectRatio: 1.8,
      children: [
        for (final (label, key) in _keys)
          InkWell(
            borderRadius: BorderRadius.circular(MobileTokens.radiusAvatar),
            onTap: () => onKey(key),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(MobileTokens.radiusAvatar),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
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
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Search snippets',
              prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: Text('No snippets',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final s = shown[i];
                    return ListTile(
                      title: Text(s.label,
                          style: const TextStyle(color: AppColors.textPrimary)),
                      subtitle: Text(s.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                      onTap: () => widget.onInsert(s.command),
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
              style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final cmd = entries[i]; // entries is already newest-first (addFirst)
        return ListTile(
          title: Text(cmd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontFamily: 'monospace', fontSize: 13)),
          onTap: () => onInsert(cmd),
        );
      },
    );
  }
}
