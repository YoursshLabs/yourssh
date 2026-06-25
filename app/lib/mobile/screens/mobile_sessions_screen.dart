import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../models/ssh_session.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';

/// Sessions tab: a session strip + the active SSH session's terminal (when
/// connected) or its connection status. The accessory key bar (M2.2) docks
/// below the terminal.
class MobileSessionsScreen extends StatelessWidget {
  const MobileSessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final ssh = sp.sshSessions;

    if (ssh.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('No active sessions — connect from Hosts',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final active = sp.activeSession is SshSession
        ? sp.activeSession as SshSession
        : ssh.last;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _SessionStrip(sessions: ssh, activeId: active.id),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _SessionBody(session: active)),
          ],
        ),
      ),
    );
  }
}

class _SessionStrip extends StatelessWidget {
  final List<SshSession> sessions;
  final String activeId;
  const _SessionStrip({required this.sessions, required this.activeId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(s.tabLabel),
                selected: s.id == activeId,
                onSelected: (_) =>
                    context.read<SessionProvider>().setActive(s.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  final SshSession session;
  const _SessionBody({required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.status == SessionStatus.connected) {
      return TerminalView(session.terminal);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.status == SessionStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(),
            ),
          Text(session.statusLabel,
              style: const TextStyle(color: AppColors.textSecondary)),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(session.errorMessage!,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
