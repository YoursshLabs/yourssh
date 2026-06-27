import 'package:flutter/material.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// Compact pill for a host tag or a filter chip. [selected] fills it with the
/// accent color; tappable when [onTap] is provided.
///
/// [large] switches to the folder-filter style used in the Hosts header
/// (uniform 15/7 padding, 13px text, no border) so short labels like "All"
/// stay pill-shaped instead of collapsing to a circle. The default (badge)
/// style is the tiny tag pill shown on host cards.
class TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool large;
  final VoidCallback? onTap;

  const TagChip({
    super.key,
    required this.label,
    this.selected = false,
    this.large = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : MobileColors.textMuted;
    final bg = selected
        ? MobileColors.accent
        : (large ? MobileColors.fieldFill : MobileColors.surface);
    final chip = Container(
      // Large (folder/category filter) chips get a min width + centered text so
      // short labels like "All"/"logs" don't look cramped next to longer ones.
      constraints: large ? const BoxConstraints(minWidth: 64) : null,
      alignment: large ? Alignment.center : null,
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
          : const EdgeInsets.symmetric(
              horizontal: MobileTokens.space2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: large ? null : Border.all(color: MobileColors.border),
      ),
      child: large
          ? Text(
              label,
              textAlign: TextAlign.center,
              style: mobileBody(
                size: 13,
                color: fg,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
              ).copyWith(height: 1.0),
            )
          : Text(label, style: TextStyle(color: fg, fontSize: 11)),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: chip,
    );
  }
}
