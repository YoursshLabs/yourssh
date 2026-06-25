import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/known_host.dart';
import '../../providers/known_hosts_provider.dart';
import '../../theme/app_theme.dart';

/// Watches [KnownHostsProvider.pendingChallenge] and shows a single TOFU
/// host-key-mismatch dialog (Trust / Reject) when a key changes.
class TofuWatcher extends StatefulWidget {
  final Widget child;
  const TofuWatcher({super.key, required this.child});

  @override
  State<TofuWatcher> createState() => _TofuWatcherState();
}

class _TofuWatcherState extends State<TofuWatcher> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<KnownHostsProvider>().pendingChallenge;
    if (challenge != null && !_dialogOpen) {
      _dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _show(challenge);
        } else {
          challenge.reject(); // never leave the connect future hanging
        }
      });
    }
    return widget.child;
  }

  Future<void> _show(HostKeyChallenge c) async {
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Host key changed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'The host key for ${c.host}:${c.port} has changed. This could '
                'be a server reinstall — or a man-in-the-middle attack.',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Old: ${c.oldFingerprint}',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace')),
            Text('New: ${c.newFingerprint}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Reject')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Trust')),
        ],
      ),
    );
    c.resolve(accept == true);
    _dialogOpen = false;
  }
}
