import 'package:flutter/material.dart';

import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// 56-px rounded-square (r18) amber FAB with a white "+" icon.
class MobileFab extends StatelessWidget {
  const MobileFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: MobileTokens.fabSize,
        height: MobileTokens.fabSize,
        decoration: BoxDecoration(
          color: MobileColors.accent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
