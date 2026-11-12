import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/known_host.dart';
import '../theme/app_theme.dart';

// ── Host Key Mismatch Dialog ──────────────────────────────

/// Shared chrome for TOFU trust prompts (SSH host key, RDP certificate) —
/// one dialog skeleton so the two security prompts can't visually diverge.
class TofuDialog extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String endpoint;
  final List<Widget> fingerprintRows;
  final String warning;
  final String cancelLabel;
  final String acceptLabel;

  /// Accepting is a security downgrade (changed key / changed certificate):
  /// the accept button uses the destructive variant.
  final bool destructiveAccept;

  const TofuDialog({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.endpoint,
    required this.fingerprintRows,
    required this.warning,
    required this.cancelLabel,
    required this.acceptLabel,
    this.destructiveAccept = false,
  });

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      semanticsLabel: title,
      titleWidget: Row(
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(title)),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            endpoint,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ...fingerprintRows,
          const SizedBox(height: 12),
          Text(
            warning,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
      actions: [
        // Safe choice (reject) holds default focus: a stray Enter never
        // trusts an unverified key/certificate.
        FButton(
          autofocus: true,
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FButton(
          variant: destructiveAccept
              ? FButtonVariant.destructive
              : FButtonVariant.primary,
          onPress: () => Navigator.of(context).pop(true),
          child: Text(acceptLabel),
        ),
      ],
    );
  }
}

class HostKeyDialog extends StatelessWidget {
  final HostKeyChallenge challenge;
  const HostKeyDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final typeChanged = challenge.isKeyTypeChange;
    return TofuDialog(
      icon: Icons.warning_amber_rounded,
      accentColor: Colors.orange,
      title: typeChanged ? 'Host key type changed' : 'Host key changed',
      endpoint: '${challenge.host}:${challenge.port}',
      fingerprintRows: [
        FpRow(
            label: typeChanged ? 'Old (${challenge.oldKeyType})' : 'Old',
            fp: challenge.oldFingerprint),
        const SizedBox(height: 4),
        FpRow(
            label: typeChanged ? 'New (${challenge.keyType})' : 'New',
            fp: challenge.newFingerprint),
      ],
      warning: typeChanged
          ? 'This server is trusted under a ${challenge.oldKeyType} key but now '
              'presents a ${challenge.keyType} key. This could indicate a '
              'man-in-the-middle attack. Only trust it if you know the server '
              'now offers this key type.'
          : 'This could indicate a man-in-the-middle attack. '
              'Only trust the new key if you know the server key changed.',
      cancelLabel: 'Cancel',
      acceptLabel: 'Trust new key',
      destructiveAccept: true,
    );
  }
}

// ── RDP Certificate TOFU Dialog ───────────────────────────

class RdpCertDialog extends StatelessWidget {
  final RdpCertChallenge challenge;
  const RdpCertDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final mismatch = challenge.isMismatch;
    return TofuDialog(
      icon: mismatch ? Icons.warning_amber_rounded : Icons.lock_open,
      accentColor: mismatch ? AppColors.red : AppColors.accent,
      title: mismatch ? 'RDP certificate changed' : 'Trust RDP certificate?',
      endpoint: '${challenge.host}:${challenge.port}',
      fingerprintRows: [
        FpRow(label: 'SHA-256', fp: challenge.fingerprint),
      ],
      warning: mismatch
          ? 'The server certificate has changed since you last connected. '
              'This could indicate a man-in-the-middle attack. The connection '
              'was aborted before your credentials were sent.'
          : 'This server\'s certificate is not yet trusted. '
              'Verify the fingerprint above before accepting.',
      cancelLabel: 'Reject',
      acceptLabel: mismatch ? 'Trust new cert' : 'Accept',
      destructiveAccept: mismatch,
    );
  }
}

class FpRow extends StatelessWidget {
  final String label;
  final String fp;
  const FpRow({required this.label, required this.fp});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // Wide enough for 'SHA-256:' — 34px wrapped it mid-label.
          width: 60,
          child: Text('$label:',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: Text(fp,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

