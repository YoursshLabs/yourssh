import 'package:flutter/material.dart';

import '../../models/host.dart';
import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';
import 'host_avatar.dart';
import 'mobile_card.dart';
import 'status_dot.dart';
import 'tag_chip.dart';

/// Termius-style host row: seeded avatar + label + user@host:port + tag chips,
/// with a connection status dot and a trailing chevron.
class HostCard extends StatelessWidget {
  final Host host;
  final HostConnState state;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const HostCard({
    super.key,
    required this.host,
    required this.state,
    required this.onTap,
    this.onLongPress,
  });

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
            HostAvatar(label: host.label, seed: host.host),
            const SizedBox(width: MobileTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          host.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      StatusDot(state: state),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${host.username}@${host.host}:${host.port}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
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
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
