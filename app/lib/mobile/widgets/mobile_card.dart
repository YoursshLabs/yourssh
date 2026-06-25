import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(MobileTokens.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(MobileTokens.space3),
          child: child,
        ),
      ),
    );
  }
}
