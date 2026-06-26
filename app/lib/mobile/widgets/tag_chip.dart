import 'package:flutter/material.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// Compact pill for a host tag or a filter chip. [selected] fills it with the
/// accent color; tappable when [onTap] is provided.
class TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const TagChip({super.key, required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : MobileColors.textMuted;
    final bg = selected ? MobileColors.accent : MobileColors.surface;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: Border.all(color: MobileColors.border),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11)),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: chip,
    );
  }
}
