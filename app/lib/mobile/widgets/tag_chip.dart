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
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 15, vertical: 7)
          : const EdgeInsets.symmetric(
              horizontal: MobileTokens.space2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: large ? null : Border.all(color: MobileColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: large ? 13 : 11,
          fontWeight: large
              ? (selected ? FontWeight.w600 : FontWeight.w500)
              : FontWeight.normal,
        ),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: chip,
    );
  }
}
