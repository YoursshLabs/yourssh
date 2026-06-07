import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small "RDP" pill marking remote-desktop hosts. One widget shared by the
/// dashboard cards, the compact list rows, and the host detail header so a
/// restyle can't leave the three call sites visually diverged.
class RdpBadge extends StatelessWidget {
  const RdpBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: AppColors.blue.withValues(alpha: 0.4), width: 0.5),
      ),
      child: const Text(
        'RDP',
        style: TextStyle(
            color: AppColors.blue, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }
}
