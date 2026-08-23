import 'package:flutter/material.dart';

import '../../models/host.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import 'host_avatar.dart';
import 'latency_badge.dart';
import 'mobile_card.dart';
import 'status_dot.dart';
import 'tag_chip.dart';

/// Termius-style host row: seeded avatar (with status dot overlay) + label
/// + user@ip (mono, faint) + latency badge + chevron.
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
      child: MobileCard(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            HostAvatar(
              label: host.label,
              seed: host.host,
              statusState: _connState,
            ),
            const SizedBox(width: MobileTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mobileBody(
                      size: 15.5,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mobileMono(
                      size: 12.5,
                      color: MobileColors.textFaint,
                    ),
                  ),
                  if (host.tags.isNotEmpty) ...[
                    const SizedBox(height: MobileTokens.space2),
                    Wrap(
                      spacing: MobileTokens.space1 + 2,
                      runSpacing: MobileTokens.space1,
                      children: [for (final tag in host.tags) TagChip(label: tag)],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: MobileTokens.space2),
            if (!online && !connecting)
              const LatencyBadge(offline: true)
            else if (latencyMs != null)
              LatencyBadge(ms: latencyMs)
            else
              const SizedBox.shrink(),
            const SizedBox(width: MobileTokens.space1),
            const Icon(
              Icons.chevron_right,
              color: MobileColors.textFaint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
