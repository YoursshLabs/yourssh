import 'package:flutter/material.dart';

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
        style: MobileTokens.sectionLabel(),
      ),
    );
  }
}
