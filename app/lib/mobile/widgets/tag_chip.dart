import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Compact pill for a host tag or a filter chip. [selected] tints it with the
/// accent; tappable when [onTap] is provided.
class TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const TagChip({super.key, required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : AppColors.textSecondary;
    final bg = selected ? AppColors.accent : AppColors.bg;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: Border.all(color: AppColors.border),
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
