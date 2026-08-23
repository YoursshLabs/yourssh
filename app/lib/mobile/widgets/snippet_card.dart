import 'package:flutter/material.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'mobile_card.dart';
import 'tag_chip.dart';

/// Card for a single [Snippet]: title + category tag + monospace command.
/// Tapping fires [onTap].
class SnippetCard extends StatelessWidget {
  final Snippet snippet;
  final VoidCallback onTap;

  const SnippetCard({
    super.key,
    required this.snippet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MobileTokens.space2),
      child: MobileCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row + tag ───────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    snippet.label,
                    style: mobileBody(size: 15, weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (snippet.tag.isNotEmpty) ...[
                  const SizedBox(width: MobileTokens.space2),
                  TagChip(label: snippet.tag),
                ],
              ],
            ),
            const SizedBox(height: MobileTokens.space1),
            // ── Command (mono, faint) ─────────────────────────────────────
            Text(
              snippet.command,
              style: mobileMono(size: 12, color: MobileColors.textFaint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
