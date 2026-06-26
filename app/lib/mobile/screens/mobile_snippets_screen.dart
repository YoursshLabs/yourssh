import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../providers/session_provider.dart';
import '../../services/ssh_service.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/snippet_card.dart';
import '../widgets/tag_chip.dart';

/// Snippets tab — lists saved commands with a category filter.
/// Tapping a card sends the command into the active SSH session.
class MobileSnippetsScreen extends StatefulWidget {
  const MobileSnippetsScreen({super.key});

  @override
  State<MobileSnippetsScreen> createState() => _MobileSnippetsScreenState();
}

class _MobileSnippetsScreenState extends State<MobileSnippetsScreen> {
  // null means "All"
  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    final snippetProv = context.watch<SnippetProvider>();
    final sessionProv = context.watch<SessionProvider>();
    final activeSession = sessionProv.activeSshSession;

    final allSnippets = snippetProv.snippets;

    // Collect distinct non-empty tags in insertion order.
    final tags = <String>[];
    for (final s in allSnippets) {
      if (s.tag.isNotEmpty && !tags.contains(s.tag)) tags.add(s.tag);
    }

    final shown = _selectedTag == null
        ? allSnippets
        : allSnippets.where((s) => s.tag == _selectedTag).toList();

    final subtitle = activeSession != null
        ? 'Tap to run on ${activeSession.host.label}'
        : 'No active session';

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space4,
                MobileTokens.space4,
                MobileTokens.space4,
                MobileTokens.space2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Snippets',
                    style: mobileHeading(size: 30, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: MobileTokens.space1),
                  Text(
                    subtitle,
                    style: mobileBody(size: 13, color: MobileColors.textMuted),
                  ),
                ],
              ),
            ),

            // ── Category filter chips ────────────────────────────────────────
            if (tags.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MobileTokens.space4),
                  scrollDirection: Axis.horizontal,
                  children: [
                    TagChip(
                      label: 'All',
                      selected: _selectedTag == null,
                      onTap: () => setState(() => _selectedTag = null),
                    ),
                    for (final tag in tags) ...[
                      const SizedBox(width: MobileTokens.space2),
                      TagChip(
                        label: tag,
                        selected: _selectedTag == tag,
                        onTap: () => setState(() => _selectedTag = tag),
                      ),
                    ],
                  ],
                ),
              ),

            const SizedBox(height: MobileTokens.space3),

            // ── Snippet list ─────────────────────────────────────────────────
            Expanded(
              child: shown.isEmpty
                  ? _EmptyState(hasFilter: _selectedTag != null)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: MobileTokens.space4),
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final snippet = shown[i];
                        return SnippetCard(
                          key: ValueKey(snippet.id),
                          snippet: snippet,
                          onTap: () => _run(context, snippet, activeSession?.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _run(BuildContext context, Snippet snippet, String? sessionId) {
    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active session')),
      );
      return;
    }
    context.read<SshService>().sendInput(sessionId, '${snippet.command}\n');
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.code_off_outlined,
              size: 48, color: MobileColors.textFaint),
          const SizedBox(height: MobileTokens.space3),
          Text(
            hasFilter ? 'No snippets in this category' : 'No snippets yet',
            style: mobileHeading(size: 17),
          ),
        ],
      ),
    );
  }
}
