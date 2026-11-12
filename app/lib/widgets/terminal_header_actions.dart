import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/app_session.dart';
import '../models/ssh_session.dart';
import '../providers/share_provider.dart';
import 'network_stats_overlay.dart';
import 'share_session_dialog.dart';

/// Right end of the terminal workspace header (`SplitTerminalView`'s
/// `toolbarTrailing`): network stats (opt-in setting), Share (connected SSH
/// sessions, Supabase configured) and the AI chat toggle (an AI provider is
/// configured). Each control hides itself when it does not apply.
class TerminalHeaderActions extends StatelessWidget {
  final AppSession active;
  final bool aiConfigured;
  final bool aiOpen;
  final VoidCallback onToggleAi;

  const TerminalHeaderActions({
    super.key,
    required this.active,
    required this.aiConfigured,
    required this.aiOpen,
    required this.onToggleAi,
  });

  @override
  Widget build(BuildContext context) {
    final session = active;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const NetworkStatsOverlay(),
        if (session is SshSession) ...[
          const SizedBox(width: YsSpace.s1),
          ShareTerminalButton(session: session),
        ],
        if (aiConfigured) ...[
          const SizedBox(width: YsSpace.s1),
          AiChatToggle(open: aiOpen, onToggle: onToggleAi),
        ],
      ],
    );
  }
}

/// Opens [ShareSessionDialog] for [session]; amber while sharing is active.
class ShareTerminalButton extends StatelessWidget {
  final SshSession session;
  const ShareTerminalButton({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    if (!share.canShare || session.isWatch) return const SizedBox.shrink();
    if (session.status != SessionStatus.connected) {
      return const SizedBox.shrink();
    }

    final isActive = share.isSharing;
    return Tooltip(
      message: isActive ? 'Sharing active' : 'Share this terminal',
      child: FButton.icon(
        key: const Key('share-terminal-button'),
        variant: isActive ? .secondary : .ghost,
        size: .sm,
        selected: isActive,
        onPress: () => showYsDialog(
          context,
          builder: (_) => ShareSessionDialog(sessionId: session.id),
        ),
        child: Icon(
          FLucideIcons.screenShare,
          color: isActive ? YsColors.accentText : YsColors.mutedForeground,
        ),
      ),
    );
  }
}

/// Opens / closes the AI chat sidebar.
class AiChatToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  const AiChatToggle({super.key, required this.open, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final fg = open ? YsColors.accentText : YsColors.mutedForeground;
    return Tooltip(
      message: open ? 'Close AI Chat' : 'Open AI Chat',
      child: FButton(
        key: const Key('ai-chat-toggle'),
        variant: open ? .secondary : .ghost,
        size: .sm,
        selected: open,
        mainAxisSize: MainAxisSize.min,
        onPress: onToggle,
        prefix: Icon(FLucideIcons.bot, color: fg),
        child: Text('AI', style: TextStyle(color: fg)),
      ),
    );
  }
}
