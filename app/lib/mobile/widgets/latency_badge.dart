import 'package:flutter/material.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// Compact pill showing latency in ms (green when fast) or "offline" in grey.
class LatencyBadge extends StatelessWidget {
  final int? ms;
  final bool offline;

  const LatencyBadge({super.key, this.ms, this.offline = false});

  @override
  Widget build(BuildContext context) {
    final color = offline ? MobileColors.textFaint : MobileColors.green;
    final label = offline ? 'offline' : '${ms}ms';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      ),
      child: Text(
        label,
        style: mobileMono(size: 11, color: Colors.black, weight: FontWeight.w600),
      ),
    );
  }
}
