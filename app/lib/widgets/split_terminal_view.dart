import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../models/audit_event.dart';
import '../models/local_session.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/plugin_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../providers/session_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../services/audit_service.dart';
import '../services/ssh_service.dart';
import '../providers/share_provider.dart';
import 'local_terminal_pane.dart';
import 'terminal_view.dart';
import 'terminal_input_bar.dart';
import 'broadcast_toolbar.dart';
import 'terminal_config_panel.dart';
import 'terminal_snippets_panel.dart';
import 'terminal_header_chips.dart';
import 'terminal_status_bar.dart';

class SplitTerminalView extends StatelessWidget {
  final VoidCallback? onNavigateToSettings;

  /// Extra controls at the right end of the workspace header.
  final Widget? toolbarTrailing;
  const SplitTerminalView(
      {super.key, this.onNavigateToSettings, this.toolbarTrailing});

  void _sendCommand(TerminalSession session, String command) {
    session.terminal.textInput(command);
  }

  void _broadcastCommand(
    BuildContext context,
    List<TerminalSession> sessions,
    String command,
    TerminalLayoutProvider layout, {
    required String sourceSessionId,
  }) {
    if (!layout.broadcastEnabled) return;
    for (final s in sessions) {
      s.terminal.textInput(command);
    }
    // A broadcast to N hosts must show N audit rows, not 1: the focused
    // pane's input bar audits itself; record every OTHER target here.
    try {
      final audit = context.read<AuditService>();
      final cmd = command.endsWith('\n')
          ? command.substring(0, command.length - 1)
          : command;
      for (final s in sessions) {
        if (s.id == sourceSessionId) continue;
        audit.record(AuditEvent.now(
          type: AuditEventType.input,
          host: s is SshSession ? s.host : null,
          sessionId: s.id,
          command: cmd,
          meta: const {'source': 'input-bar-broadcast'},
        ));
      }
    } on ProviderNotFoundException {
      // Tests pumped without audit wiring.
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TerminalLayoutProvider>();
    final snippetsEnabled = context
        .watch<PluginProvider>()
        .isEnabled(YourSSHSnippetsPlugin.pluginId);
    final sessionProvider = context.watch<SessionProvider>();
    final termSessions = sessionProvider.sessions.whereType<TerminalSession>().toList();
    final activeRaw = sessionProvider.activeSession;
    final active = activeRaw is TerminalSession ? activeRaw : (termSessions.isNotEmpty ? termSessions[0] : null);

    if (termSessions.isEmpty) {
      return const YsEmptyState(
        icon: FLucideIcons.terminal,
        title: 'No active sessions',
      );
    }

    return Column(
      children: [
        BroadcastToolbar(
          leading: active == null
              ? null
              : TerminalHeaderChips(key: ValueKey(active.id), session: active),
          trailing: toolbarTrailing,
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildPanes(context, layout, termSessions, active)),
              // Gated on the plugin too: the panel must vanish if the
              // snippets plugin is disabled while it is open.
              if (snippetsEnabled && layout.snippetsPanelVisible)
                TerminalSnippetsPanel(
                  canRun: _canRunSnippetTarget(context),
                  onRunSnippet: (snippet) =>
                      _runSnippetOnActive(context, snippet.command),
                  onClose: layout.toggleSnippetsPanel,
                ),
              if (layout.configPanelVisible)
                TerminalConfigPanel(
                  onClose: () =>
                      layout.toggleSidePanel(SidePanel.terminalConfig),
                  onOpenSettings: onNavigateToSettings,
                ),
            ],
          ),
        ),
        if (active != null)
          SessionStatusBar(key: ValueKey(active.id), session: active),
      ],
    );
  }

  bool _canRunSnippetTarget(BuildContext context) {
    final active = context.read<SessionProvider>().activeSession;
    return switch (active) {
      SshSession s => !s.isWatch && s.status == SessionStatus.connected,
      LocalSession s => s.status == LocalSessionStatus.running,
      _ => false,
    };
  }

  void _runSnippetOnActive(BuildContext context, String command) {
    if (!_canRunSnippetTarget(context)) return;
    (context.read<SessionProvider>().activeSession! as TerminalSession)
        .terminal
        .textInput('$command\n');
  }

  Widget _buildPanes(BuildContext context, TerminalLayoutProvider layout, List<TerminalSession> sessions, TerminalSession? active) {
    final pane0 = active ?? sessions[0];
    switch (layout.layout) {
      case SplitLayout.single:
        return _buildPane(context, 0, pane0, sessions, layout);

      case SplitLayout.horizontal:
        return Row(children: [
          Expanded(child: _buildPane(context, 0, sessions[0], sessions, layout)),
          const _SplitDivider.vertical(),
          Expanded(
            child: sessions.length > 1
                ? _buildPane(context, 1, sessions[1], sessions, layout)
                : _buildEmptyPane(),
          ),
        ]);

      case SplitLayout.vertical:
        return Column(children: [
          Expanded(child: _buildPane(context, 0, sessions[0], sessions, layout)),
          const _SplitDivider.horizontal(),
          Expanded(
            child: sessions.length > 1
                ? _buildPane(context, 1, sessions[1], sessions, layout)
                : _buildEmptyPane(),
          ),
        ]);

      case SplitLayout.quad:
        return Column(children: [
          Expanded(
            child: Row(children: [
              Expanded(child: _buildPane(context, 0, sessions[0], sessions, layout)),
              const _SplitDivider.vertical(),
              Expanded(
                child: sessions.length > 1
                    ? _buildPane(context, 1, sessions[1], sessions, layout)
                    : _buildEmptyPane(),
              ),
            ]),
          ),
          const _SplitDivider.horizontal(),
          Expanded(
            child: Row(children: [
              Expanded(
                child: sessions.length > 2
                    ? _buildPane(context, 2, sessions[2], sessions, layout)
                    : _buildEmptyPane(),
              ),
              const _SplitDivider.vertical(),
              Expanded(
                child: sessions.length > 3
                    ? _buildPane(context, 3, sessions[3], sessions, layout)
                    : _buildEmptyPane(),
              ),
            ]),
          ),
        ]);
    }
  }

  Widget _buildEmptyPane() {
    return const Center(
      child: Text('No session',
          style: TextStyle(color: YsColors.mutedForeground, fontSize: 13)),
    );
  }

  Widget _buildPane(
    BuildContext context,
    int paneIndex,
    TerminalSession session,
    List<TerminalSession> allSessions,
    TerminalLayoutProvider layout,
  ) {
    // Pane 0 reflects the global inputBarVisible toggle; other panes use it too
    // when broadcast is on, otherwise only pane 0 gets the bar from the hotkey
    final showInput = layout.inputBarVisible && paneIndex == 0 ||
        (layout.inputBarVisible && layout.broadcastEnabled);

    return Column(
      children: [
        if (session is SshSession && session.isWatch)
          _WatchBanner(session: session),
        Expanded(
          child: GestureDetector(
            onTap: () => context.read<SessionProvider>().setActive(session.id),
            child: _paneContent(context, session),
          ),
        ),
        if (showInput)
          TerminalInputBar(
            sessionId: session.id,
            cwd: context.select<ShellIntegrationProvider, String?>(
                (p) => p.cwdFor(session.id)),
            // Path completion needs a remote lister — SSH only.
            listDir: session is SshSession
                ? (dir) =>
                    context.read<SshService>().listDirectory(session.host, dir)
                : null,
            onSubmit: (cmd) {
              if (layout.broadcastEnabled) {
                _broadcastCommand(context, allSessions, cmd, layout,
                    sourceSessionId: session.id);
              } else {
                _sendCommand(session, cmd);
              }
            },
            onDismiss: () => layout.toggleInputBar(),
          ),
      ],
    );
  }

  Widget _paneContent(BuildContext context, TerminalSession session) {
    // Exhaustive over the known session types — a future third type must
    // fail loudly here instead of being silently treated as SSH.
    return switch (session) {
      LocalSession() => LocalTerminalPane(
          key: ValueKey(session.id),
          session: session,
          onRestart: () =>
              context.read<SessionProvider>().restartLocalSession(session.id),
        ),
      SshSession() =>
        SessionTerminalView(key: ValueKey(session.id), session: session),
      _ => throw UnsupportedError(
          'Unknown TerminalSession type: ${session.runtimeType}'),
    };
  }
}

/// 1 px token-coloured pane separator. [vertical] separates side-by-side
/// panes (a vertical line); the other separates stacked panes.
class _SplitDivider extends StatelessWidget {
  final bool vertical;
  const _SplitDivider.vertical() : vertical = true;
  const _SplitDivider.horizontal() : vertical = false;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const Key('split-divider'),
        width: vertical ? 1 : null,
        height: vertical ? null : 1,
        child: const ColoredBox(color: YsColors.border),
      );
}

class _WatchBanner extends StatelessWidget {
  final SshSession session;
  const _WatchBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final share = context.watch<ShareProvider>();
    final hasControl = share.isGuest && share.hasControl;
    final sessionEnded = share.isGuest && share.sessionEnded;

    Color bg;
    Color fg;
    String label;

    if (sessionEnded) {
      bg = YsColors.error.withValues(alpha: 0.14);
      fg = YsColors.error;
      label = 'Session ended by host';
    } else if (hasControl) {
      bg = YsColors.ok.withValues(alpha: 0.12);
      fg = YsColors.ok;
      label = 'You have control';
    } else {
      // Informational: primary tint + amber text, distinct from the green
      // in-control and red ended states.
      bg = YsColors.primary.withValues(alpha: 0.12);
      fg = YsColors.accentText;
      label = 'Watching: ${session.watchedTitle ?? ''} · Read-only';
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          Icon(FLucideIcons.screenShare, size: 12, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontSize: 11)),
          const Spacer(),
          if (!sessionEnded)
            GestureDetector(
              onTap: () => context.read<ShareProvider>().leaveSession(),
              child: Text('Leave', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
