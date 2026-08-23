import 'package:flutter/material.dart';

import '../../models/port_forward.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'mobile_card.dart';

/// A single port-forward rule card: type chip + state dot + mono summary + toggle.
class ForwardRuleRow extends StatelessWidget {
  final PortForward rule;
  final bool isRunning;
  final VoidCallback onToggle;

  const ForwardRuleRow({
    super.key,
    required this.rule,
    required this.isRunning,
    required this.onToggle,
  });

  String get _typeLabel => switch (rule.type) {
        ForwardType.local => 'LOCAL',
        ForwardType.remote => 'REMOTE',
        ForwardType.dynamic => 'DYNAMIC',
      };

  String get _monoLine => switch (rule.type) {
        ForwardType.local =>
          ':${rule.localPort} → ${rule.remoteHost}:${rule.remotePort}',
        ForwardType.remote =>
          'Remote :${rule.remotePort} → :${rule.localPort}',
        ForwardType.dynamic => 'SOCKS5 :${rule.localPort}',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space1,
      ),
      child: MobileCard(
        child: Row(
          children: [
            // Type chip
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: MobileColors.accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _typeLabel,
                style: mobileMono(
                  size: 10,
                  color: MobileColors.accent,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: MobileTokens.space2),
            // State dot
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: isRunning ? MobileColors.green : MobileColors.textFaint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: MobileTokens.space2),
            // Mono rule line
            Expanded(
              child: Text(
                _monoLine,
                style: mobileMono(size: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Start / stop toggle
            IconButton(
              icon: Icon(
                isRunning
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
                color: isRunning ? MobileColors.red : MobileColors.green,
                size: 22,
              ),
              tooltip: isRunning ? 'Stop' : 'Start',
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}
