import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../models/local_session.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/plugin_provider.dart';
import '../providers/terminal_layout_provider.dart';
import '../providers/session_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../services/ssh_service.dart';
import '../providers/share_provider.dart';
import 'local_terminal_pane.dart';
import 'terminal_view.dart';
import 'terminal_input_bar.dart';
import 'broadcast_toolbar.dart';
import 'terminal_config_panel.dart';
import 'terminal_snippets_panel.dart';

class SplitTerminalView extends StatelessWidget {
  const SplitTerminalView({super.key});

  void _sendCommand(TerminalSession session, String command) {
    session.terminal.textInput(command);
  }

  void _broadcastCommand(
    List<TerminalSession> sessions,
    String command,
    TerminalLayoutProvider layout,
  ) {
    if (!layout.broadcastEnabled) return;
    for (final s in sessions) {
      s.terminal.textInput(command);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<TerminalLayoutProvider>();
    final snippetsEnabled = context
        .watch<PluginProvider>()
        .isEnabled(YourSSHSnippetsPlugin.pluginId);
    final sessionProvider = context.watch<SessionProvider>();
    final sessions = sessionProvider.sessions;
    final active = sessionProvider.activeSession;

    if (sessions.isEmpty) {
      return const Center(
        child: Text('No active sessions', style: TextStyle(color: Color(0xFF555555))),
      );
    }

    return Column(
      children: [
        const BroadcastToolbar(),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildPanes(context, layout, sessions, active)),
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
                ),
            ],
          ),
        ),
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
    context
        .read<SessionProvider>()
        .activeSession!
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
          const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
          Expanded(
            child: sessions.length > 1
                ? _buildPane(context, 1, sessions[1], sessions, layout)
                : _buildEmptyPane(),
          ),
        ]);

      case SplitLayout.vertical:
        return Column(children: [
          Expanded(child: _buildPane(context, 0, sessions[0], sessions, layout)),
          const Divider(height: 1, color: Color(0xFF2A2A2A)),
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
              const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
              Expanded(
                child: sessions.length > 1
                    ? _buildPane(context, 1, sessions[1], sessions, layout)
                    : _buildEmptyPane(),
              ),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF2A2A2A)),
          Expanded(
            child: Row(children: [
              Expanded(
                child: sessions.length > 2
                    ? _buildPane(context, 2, sessions[2], sessions, layout)
                    : _buildEmptyPane(),
              ),
              const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
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
      child: Text('No session', style: TextStyle(color: Color(0xFF555555), fontSize: 13)),
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
                _broadcastCommand(allSessions, cmd, layout);
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
      bg = const Color(0xFF2A1A1A);
      fg = const Color(0xFFCC4444);
      label = 'Session ended by host';
    } else if (hasControl) {
      bg = const Color(0xFF1A2A1A);
      fg = const Color(0xFF22C55E);
      label = 'You have control';
    } else {
      bg = const Color(0xFF1A1A2A);
      fg = const Color(0xFF6699CC);
      label = 'Watching: ${session.watchedTitle ?? ''} · Read-only';
    }

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.screen_share_outlined, size: 12, color: fg),
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
