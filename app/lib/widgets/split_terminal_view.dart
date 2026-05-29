// app/lib/widgets/split_terminal_view.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ssh_session.dart';
import '../providers/terminal_layout_provider.dart';
import '../providers/session_provider.dart';
import 'terminal_view.dart';
import 'terminal_input_bar.dart';
import 'broadcast_toolbar.dart';

class SplitTerminalView extends StatefulWidget {
  const SplitTerminalView({super.key});

  @override
  State<SplitTerminalView> createState() => _SplitTerminalViewState();
}

class _SplitTerminalViewState extends State<SplitTerminalView> {
  final Map<int, bool> _inputBarVisible = {};

  void _toggleInputBar(int paneIndex) {
    setState(() {
      _inputBarVisible[paneIndex] = !(_inputBarVisible[paneIndex] ?? false);
    });
  }

  void _sendCommand(SshSession session, String command) {
    session.terminal.textInput(command);
  }

  void _broadcastCommand(
    List<SshSession> sessions,
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
    final sessions = context.watch<SessionProvider>().sessions;

    if (sessions.isEmpty) {
      return const Center(
        child: Text('No active sessions', style: TextStyle(color: Color(0xFF555555))),
      );
    }

    return Column(
      children: [
        const BroadcastToolbar(),
        Expanded(child: _buildPanes(layout, sessions)),
      ],
    );
  }

  Widget _buildPanes(TerminalLayoutProvider layout, List<SshSession> sessions) {
    switch (layout.layout) {
      case SplitLayout.single:
        return _buildPane(0, sessions[0], sessions, layout);

      case SplitLayout.horizontal:
        return Row(children: [
          Expanded(child: _buildPane(0, sessions[0], sessions, layout)),
          const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
          if (sessions.length > 1)
            Expanded(child: _buildPane(1, sessions[1], sessions, layout)),
        ]);

      case SplitLayout.vertical:
        return Column(children: [
          Expanded(child: _buildPane(0, sessions[0], sessions, layout)),
          const Divider(height: 1, color: Color(0xFF2A2A2A)),
          if (sessions.length > 1)
            Expanded(child: _buildPane(1, sessions[1], sessions, layout)),
        ]);

      case SplitLayout.quad:
        return Column(children: [
          Expanded(
            child: Row(children: [
              Expanded(child: _buildPane(0, sessions[0], sessions, layout)),
              const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
              if (sessions.length > 1)
                Expanded(child: _buildPane(1, sessions[1], sessions, layout)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF2A2A2A)),
          Expanded(
            child: Row(children: [
              if (sessions.length > 2)
                Expanded(child: _buildPane(2, sessions[2], sessions, layout)),
              const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
              if (sessions.length > 3)
                Expanded(child: _buildPane(3, sessions[3], sessions, layout)),
            ]),
          ),
        ]);
    }
  }

  Widget _buildPane(
    int paneIndex,
    SshSession session,
    List<SshSession> allSessions,
    TerminalLayoutProvider layout,
  ) {
    final showInput = _inputBarVisible[paneIndex] ?? false;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => context.read<SessionProvider>().setActive(session.id),
            child: SessionTerminalView(session: session),
          ),
        ),
        if (showInput)
          TerminalInputBar(
            sessionId: session.id,
            onSubmit: (cmd) {
              if (layout.broadcastEnabled) {
                _broadcastCommand(allSessions, cmd, layout);
              } else {
                _sendCommand(session, cmd);
              }
            },
            onDismiss: () => _toggleInputBar(paneIndex),
          ),
      ],
    );
  }
}
