import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Uppercase, letter-spaced section label for grouped lists/settings.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: MobileTokens.space1,
        bottom: MobileTokens.space2,
        top: MobileTokens.space2,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
