import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';
import 'status_dot.dart';

/// Up to two uppercase initials from a host label. Words are whitespace-split;
/// two-plus words use the first letter of the first two words. A single word
/// starting with a letter returns its first two characters; a single word
/// starting with a non-letter (e.g. an IP address) returns only the first
/// character. Returns '' for blank input.
String hostInitials(String label) {
  final words = label.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length >= 2) {
    return (words[0][0] + words[1][0]).toUpperCase();
  }
  // Single word: take 2 chars only when the word starts with a letter.
  final w = words.first;
  if (w[0].contains(RegExp(r'[A-Za-z]')) && w.length >= 2) {
    return w.substring(0, 2).toUpperCase();
  }
  return w[0].toUpperCase();
}

/// Rounded-square avatar (radius 11): seeded background tint + initials or
/// optional [icon] glyph in the seed color. An optional [statusState] places
/// a small [StatusDot] at the bottom-right corner.
class HostAvatar extends StatelessWidget {
  final String label;
  final String seed;
  final IconData? icon;
  final double size;
  final HostConnState? statusState;

  const HostAvatar({
    super.key,
    required this.label,
    required this.seed,
    this.icon,
    this.size = MobileTokens.avatar,
    this.statusState,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.hostColor(seed);
    final initials = hostInitials(label);

    Widget tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(MobileTokens.radiusAvatar),
      ),
      child: icon != null
          ? Icon(icon, color: color, size: size * 0.5)
          : initials.isEmpty
              ? Icon(Icons.dns_outlined, color: color, size: size * 0.5)
              : Text(
                  initials,
                  style: TextStyle(
                    color: color,
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w600,
                  ),
                ),
    );

    if (statusState == null) return tile;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          right: -2,
          bottom: -2,
          child: StatusDot(state: statusState!),
        ),
      ],
    );
  }
}
