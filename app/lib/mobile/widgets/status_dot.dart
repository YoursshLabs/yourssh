import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Coarse connection state for a host row / session, decoupled from
/// [SessionStatus] so this widget stays provider-free.
enum HostConnState { connected, connecting, offline }

Color statusColor(HostConnState s) => switch (s) {
      HostConnState.connected => AppColors.accent,
      HostConnState.connecting => AppColors.orange,
      HostConnState.offline => AppColors.textTertiary,
    };

class StatusDot extends StatelessWidget {
  final HostConnState state;
  final double size;

  const StatusDot({
    super.key,
    required this.state,
    this.size = MobileTokens.statusDot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusColor(state),
        shape: BoxShape.circle,
      ),
    );
  }
}
