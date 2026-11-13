import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';

/// Layout and typography constants for the mobile UI.
/// Colors live in [MobileColors]; this file is purely spacing/sizing/typography
/// so widgets share one rhythm.
abstract final class MobileTokens {
  // ── Spacing ──────────────────────────────────────────────────────────────
  static const double space1 = YsSpace.s1;
  static const double space2 = YsSpace.s2;
  static const double space3 = YsSpace.s3;
  static const double space4 = YsSpace.s4;
  static const double space5 = YsSpace.s5;

  // ── Radii ─────────────────────────────────────────────────────────────────
  static const double radiusCard = YsRadius.mobileCard;
  static const double radiusPill   = 22;
  static const double radiusAvatar = 12;
  static const double radiusField  = 12;

  // ── Sizes ─────────────────────────────────────────────────────────────────
  static const double avatar            = 44;
  static const double statusDot         = 8;
  static const double accessoryBarHeight = 48;
  static const double touchTarget       = 44;
  static const double fabSize           = 56;
  static const double tabBarHeight      = 78;

  // ── Gaps ──────────────────────────────────────────────────────────────────
  static const double sectionLabelGap = 8;

  // ── Typography ────────────────────────────────────────────────────────────

  /// Section header label: 11 px, w600, letter-spacing 1, [MobileColors.textFaint].
  static TextStyle sectionLabel() => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: MobileColors.textFaint,
      );
}
