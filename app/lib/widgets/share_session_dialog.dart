import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../providers/share_provider.dart';

const _titleStyle = TextStyle(
  color: YsColors.foreground,
  fontSize: 16,
  fontWeight: FontWeight.w600,
);

const _mono = TextStyle(
  fontFamily: kYsMonoFontFamily,
  fontFamilyFallback: kYsMonoFontFallback,
);

/// Host side of terminal sharing: start sharing, then show the share code
/// (tap to copy), its QR, the viewers, control grant/revoke and Stop.
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
      padding: const EdgeInsets.all(YsSpace.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Share Terminal', style: _titleStyle),
          const SizedBox(height: YsSpace.s2),
          const Text(
            'Generate a share code so others can watch this terminal session in real-time.',
            style: TextStyle(color: YsColors.mutedForeground, fontSize: 13),
          ),
          const SizedBox(height: YsSpace.s1),
          const Text(
            'End-to-end encrypted with the share code.',
            style: TextStyle(color: YsColors.off, fontSize: 11),
          ),
          const SizedBox(height: YsSpace.s5 - 4),
          FButton(
            key: const Key('share-start'),
            onPress: () async {
              await share.startSharing(sessionId);
            },
            prefix: const Icon(FLucideIcons.share2),
            child: const Text('Start Sharing'),
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
    final viewers = share.guests.length;

    return Padding(
      padding: const EdgeInsets.all(YsSpace.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Sharing Live',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
              ),
              const SizedBox(width: YsSpace.s2),
              YsStatusBadge(
                '$viewers viewer${viewers == 1 ? '' : 's'}',
                status: YsStatus.accent,
              ),
            ],
          ),
          const SizedBox(height: YsSpace.s5 - 4),
          Center(
            child: Tooltip(
              message: 'Copy share code',
              child: FButton(
                key: const Key('share-code'),
                variant: .outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () {
                  Clipboard.setData(ClipboardData(text: code));
                  showYsToast(context, 'Code copied',
                      duration: const Duration(seconds: 2));
                },
                child: Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      code,
                      style: _mono.copyWith(
                        color: YsColors.accentText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: YsSpace.s1),
          const Center(
            child: Text(
              'Tap code to copy',
              style: TextStyle(color: YsColors.off, fontSize: 11),
            ),
          ),
          const SizedBox(height: YsSpace.s4),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(YsRadius.control),
              child: QrImageView(
                data: qrUrl,
                size: 140,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: YsSpace.s4),
          if (share.guests.isNotEmpty) ...[
            const FDivider(),
            if (share.controlledBy == null) ...[
              const Text(
                'Grant control',
                style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
              ),
              const SizedBox(height: YsSpace.s1 + 2),
              ...share.guests.map((guestId) => _GuestRow(
                    guestId: guestId,
                    hasControl: false,
                    onGrant: () => share.grantControl(guestId),
                    onRevoke: null,
                  )),
            ] else ...[
              const Text(
                'Control granted',
                style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
              ),
              const SizedBox(height: YsSpace.s1 + 2),
              _GuestRow(
                guestId: share.controlledBy!,
                hasControl: true,
                onGrant: null,
                onRevoke: () => share.revokeControl(),
              ),
            ],
          ],
          const SizedBox(height: YsSpace.s4),
          FButton(
            key: const Key('share-stop'),
            variant: .outline,
            onPress: () async {
              await share.stopSharing();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Stop Sharing',
              style: TextStyle(color: YsColors.error),
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
          const Icon(FLucideIcons.user, size: 14, color: YsColors.off),
          const SizedBox(width: YsSpace.s1 + 2),
          Text(
            shortId,
            style: _mono.copyWith(color: YsColors.mutedForeground, fontSize: 12),
          ),
          const Spacer(),
          if (hasControl)
            FButton(
              variant: .destructive,
              size: .xs,
              mainAxisSize: MainAxisSize.min,
              onPress: onRevoke,
              child: const Text('Revoke'),
            )
          else
            FButton(
              variant: .secondary,
              size: .xs,
              mainAxisSize: MainAxisSize.min,
              onPress: onGrant,
              child: const Text('Grant'),
            ),
        ],
      ),
    );
  }
}
