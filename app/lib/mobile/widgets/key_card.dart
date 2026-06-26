import 'package:flutter/material.dart';

import '../../models/ssh_key.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../util/ssh_fingerprint.dart';
import 'mobile_card.dart';

/// Termius-style SSH key row:
/// key-glyph tile | label + algo·hosts subtitle + fingerprint | chevron.
class KeyCard extends StatelessWidget {
  final SshKeyEntry entry;

  /// Number of hosts that reference this key.
  final int hostCount;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const KeyCard({
    super.key,
    required this.entry,
    required this.hostCount,
    this.onTap,
    this.onLongPress,
  });

  String get _subtitle {
    final algo = switch (entry.algorithm) {
      KeyAlgorithm.ed25519 => 'Ed25519',
      KeyAlgorithm.rsa => 'RSA 4096',
      KeyAlgorithm.ecdsa => 'ECDSA',
    };
    if (hostCount == 0) return '$algo · unused';
    return '$algo · $hostCount ${hostCount == 1 ? 'host' : 'hosts'}';
  }

  String get _fingerprintLine {
    final pk = entry.publicKey;
    if (pk.isEmpty) return '';
    return sha256Fingerprint(pk) ?? 'SHA256:(pending)';
  }

  @override
  Widget build(BuildContext context) {
    final fp = _fingerprintLine;

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
            // ── Key glyph tile ────────────────────────────────────────────────
            Container(
              width: MobileTokens.avatar,
              height: MobileTokens.avatar,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1A2E), // muted purple tint
                borderRadius:
                    BorderRadius.circular(MobileTokens.radiusAvatar),
              ),
              child: const Icon(
                Icons.vpn_key_rounded,
                color: Color(0xFFB99EFF), // soft lavender
                size: 22,
              ),
            ),

            const SizedBox(width: MobileTokens.space3),

            // ── Text column ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mobileBody(size: 15.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        mobileBody(size: 12.5, color: MobileColors.textMuted),
                  ),
                  if (fp.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      fp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mobileMono(
                          size: 11, color: MobileColors.textFaint),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: MobileTokens.space2),

            // ── Chevron ───────────────────────────────────────────────────────
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
