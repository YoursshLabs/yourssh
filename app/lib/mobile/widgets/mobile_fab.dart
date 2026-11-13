import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../theme/mobile_tokens.dart';

/// 56-px amber primary FAB with a "+" icon, on [FButton.icon]. Needs an
/// ancestor [FTheme] (the app root provides one).
class MobileFab extends StatelessWidget {
  const MobileFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add host',
      child: SizedBox.square(
        dimension: MobileTokens.fabSize,
        child: FButton.icon(
          variant: .primary,
          size: .lg,
          onPress: onTap,
          semanticsLabel: 'Add host',
          child: const Icon(FLucideIcons.plus, size: 28),
        ),
      ),
    );
  }
}
