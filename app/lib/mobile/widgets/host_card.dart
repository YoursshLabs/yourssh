import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/host.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'host_avatar.dart';
import 'latency_badge.dart';
import 'status_dot.dart';
import 'tag_chip.dart';

/// Host row on [YsHostCard]: seeded avatar (with status dot overlay) + label
/// + user@ip (mono) + tags + latency badge + chevron. Tap and long-press are
/// forwarded; the card is also keyboard-activatable.
class HostCard extends StatelessWidget {
  final Host host;
  final bool online;
  final bool connecting;
  final int? latencyMs;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const HostCard({
    super.key,
    required this.host,
    this.online = false,
    this.connecting = false,
    this.latencyMs,
    this.onTap,
    this.onLongPress,
  });

  HostConnState get _connState {
    if (online) return HostConnState.connected;
    if (connecting) return HostConnState.connecting;
    return HostConnState.offline;
  }

  /// Shows `user@host` — omits the port when it equals the protocol default.
  String get _subtitle {
    final defaultPort = host.protocol.defaultPort;
    if (host.port == defaultPort) return '${host.username}@${host.host}';
    return '${host.username}@${host.host}:${host.port}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space3,
        vertical: MobileTokens.space1 + 2,
      ),
      child: YsHostCard(
        leading: HostAvatar(
          label: host.label,
          seed: host.host,
          statusState: _connState,
        ),
        title: host.label,
        subtitle: _subtitle,
        tags: [for (final tag in host.tags) TagChip(label: tag)],
        onTap: onTap,
        onLongPress: onLongPress,
        trailingAction: SizedBox(
          height: MobileTokens.avatar,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!online && !connecting)
                const LatencyBadge(offline: true)
              else if (latencyMs != null)
                LatencyBadge(ms: latencyMs),
              const SizedBox(width: MobileTokens.space1),
              const Icon(
                FLucideIcons.chevronRight,
                color: MobileColors.textFaint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
