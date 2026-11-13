import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Whether a tappable in [variants] is pressed or hovered, i.e. should show
/// the shared mobile feedback tint ([YsColors.secondary]).
bool mobileIsTinted(Set<FTappableVariant> variants) =>
    variants.contains(FTappableVariant.pressed) ||
    variants.contains(FTappableVariant.hovered);

/// Wraps [child] in the hover/press tint used by `MobileCard`, `SettingsRow`
/// and `TagChip` so every tappable mobile surface gives the same feedback.
Widget mobilePressTint(Set<FTappableVariant> variants, Widget child) =>
    ColoredBox(
      color: mobileIsTinted(variants)
          ? YsColors.secondary
          : const Color(0x00000000),
      child: child,
    );
