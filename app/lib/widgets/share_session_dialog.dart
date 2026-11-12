import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/share_provider.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class ShareSessionDialog extends StatelessWidget {
  final String sessionId;
  const ShareSessionDialog({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return YsDialogFrame(
      maxWidth: 360,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 360,
        child: Consumer<ShareProvider>(
          builder: (context, share, _) {
            if (!share.isSharing) {
              return _StartSharingView(sessionId: sessionId);
            }
            return _ActiveShareView(share: share);
          },
        ),
      ),
    );
  }
}

class _StartSharingView extends StatelessWidget {
  final String sessionId;
  const _StartSharingView({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final share = context.read<ShareProvider>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Share Terminal', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Generate a share code so others can watch this terminal session in real-time.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Shared over TLS via your Supabase project.',
            style: TextStyle(color: Color(0xFF555555), fontSize: 11),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: () async {
                await share.startSharing(sessionId);
              },
              child: const Text('Start Sharing', style: TextStyle(color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveShareView extends StatelessWidget {
  final ShareProvider share;
  const _ActiveShareView({required this.share});

  @override
  Widget build(BuildContext context) {
    final code = share.shareCode ?? '';
    final qrUrl = 'yourssh://share/$code';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Sharing Live', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${share.guests.length} viewer${share.guests.length == 1 ? '' : 's'}',
                  style: TextStyle(color: AppColors.accent, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                showYsToast(context, 'Code copied',
                    duration: const Duration(seconds: 2));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('Tap code to copy', style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
          const SizedBox(height: 16),
          Center(
            child: QrImageView(
              data: qrUrl,
              size: 140,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          if (share.guests.isNotEmpty) ...[
            const Divider(color: Color(0xFF2A2A2A)),
            const SizedBox(height: 8),
            if (share.controlledBy == null) ...[
              const Text('Grant control', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              ...share.guests.map((guestId) => _GuestRow(
                guestId: guestId,
                hasControl: false,
                onGrant: () => share.grantControl(guestId),
                onRevoke: null,
              )),
            ] else ...[
              const Text('Control granted', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              _GuestRow(
                guestId: share.controlledBy!,
                hasControl: true,
                onGrant: null,
                onRevoke: () => share.revokeControl(),
              ),
            ],
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF3A3A3A)),
              ),
              onPressed: () async {
                await share.stopSharing();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Stop Sharing', style: TextStyle(color: Color(0xFFCC4444))),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  final String guestId;
  final bool hasControl;
  final VoidCallback? onGrant;
  final VoidCallback? onRevoke;

  const _GuestRow({
    required this.guestId,
    required this.hasControl,
    required this.onGrant,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final shortId = guestId.length > 8 ? guestId.substring(0, 8) : guestId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 14, color: Color(0xFF555555)),
          const SizedBox(width: 6),
          Text(shortId, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'monospace')),
          const Spacer(),
          if (hasControl)
            GestureDetector(
              onTap: onRevoke,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF440000),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Revoke', style: TextStyle(color: Color(0xFFCC4444), fontSize: 11)),
              ),
            )
          else
            GestureDetector(
              onTap: onGrant,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Grant', style: TextStyle(color: AppColors.accent, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}
