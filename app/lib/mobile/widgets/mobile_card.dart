import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'press_tint.dart';

/// The single source of card styling for the mobile UI: card surface, rounded
/// border, ripple. Used by host rows, SFTP rows, settings groups.
class MobileCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;

  const MobileCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
  });

  // Card radius per spec: 15
  static const double _radius = 15;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MobileColors.surface,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: MobileColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: _wrapTappable(
        Padding(
          padding: padding ?? const EdgeInsets.all(MobileTokens.space3),
          child: child,
        ),
      ),
    );
  }

  /// Taps/long-presses via [FTappable] with a subtle hover/press tint; plain
  /// (non-interactive) when no callback is set.
  Widget _wrapTappable(Widget content) {
    if (onTap == null && onLongPress == null) return content;
    return FTappable.static(
      onPress: onTap,
      onLongPress: onLongPress,
      builder: (context, variants, child) => mobilePressTint(variants, child!),
      child: content,
    );
  }
}
