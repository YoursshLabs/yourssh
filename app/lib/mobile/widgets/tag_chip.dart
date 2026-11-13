import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'press_tint.dart';

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

  Widget _pill({required bool tinted}) {
    final fg = selected ? Colors.black : MobileColors.textMuted;
    // Hover/press feedback, same tint as MobileCard/SettingsRow. An unselected
    // pill takes the tint as its fill; the amber selected pill gets a darker
    // overlay so it stays recognisably selected.
    final bg = selected
        ? MobileColors.accent
        : tinted
            ? YsColors.secondary
            : (large ? MobileColors.fieldFill : MobileColors.surface);
    final radius = BorderRadius.circular(MobileTokens.radiusPill);
    return Container(
      // Large (folder/category filter) chips get a min width + centered text so
      // short labels like "All"/"logs" don't look cramped next to longer ones.
      constraints: large ? const BoxConstraints(minWidth: 64) : null,
      padding: large
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
          : const EdgeInsets.symmetric(
              horizontal: MobileTokens.space2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: large ? null : Border.all(color: MobileColors.border),
      ),
      foregroundDecoration: selected && tinted
          ? BoxDecoration(color: const Color(0x1F000000), borderRadius: radius)
          : null,
      child: large
          // Centre horizontally within the min width without growing the
          // pill's height to the parent's (Container(alignment) would).
          ? Center(
              heightFactor: 1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: mobileBody(
                  size: 13,
                  color: fg,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                ).copyWith(height: 1.0),
              ),
            )
          : Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 11),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return _pill(tinted: false);
    return FTappable.static(
      selected: selected,
      onPress: onTap,
      builder: (context, variants, _) => ConstrainedBox(
        // The pill stays compact; the hit area reaches the 44 px touch minimum.
        constraints: const BoxConstraints(
          minHeight: MobileTokens.touchTarget,
          minWidth: MobileTokens.touchTarget,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: _pill(tinted: mobileIsTinted(variants)),
        ),
      ),
    );
  }
}
