import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';
import '../providers/settings_provider.dart';
import '../services/hotkey_service.dart';
import 'record_button.dart';
import 'terminal_context_menu.dart';

/// Terminal pane for a local PTY session inside the split terminal workspace.
/// Mirrors SessionTerminalView's status handling, minus SSH-only features
/// (search, shell integration, command gutter).
class LocalTerminalPane extends StatefulWidget {
  final LocalSession session;
  final VoidCallback onRestart;
  const LocalTerminalPane(
      {super.key, required this.session, required this.onRestart});

  @override
  State<LocalTerminalPane> createState() => _LocalTerminalPaneState();
}

class _LocalTerminalPaneState extends State<LocalTerminalPane> {
  final _controller = TerminalController();

  LocalSession get session => widget.session;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (session.status) {
      LocalSessionStatus.error => _statusView(
          Icons.error_outline,
          session.errorMessage ?? 'Failed to start shell',
          Colors.red,
        ),
      LocalSessionStatus.exited =>
        _statusView(Icons.link_off, 'Shell exited', Colors.grey),
      LocalSessionStatus.running => _terminal(context),
    };
  }

  Widget _terminal(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Stack(
      children: [
        TerminalView(
          key: ValueKey(session.id),
          session.terminal,
          controller: _controller,
          autofocus: true,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
          // App hotkeys (in-app scope) already fired at the HardwareKeyboard
          // layer; swallow the combo so it never reaches the shell (#46).
          onKeyEvent: (node, event) =>
              HotkeyService().shouldSwallowKeyEvent(event)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
          onSecondaryTapUp: (details, _) => showTerminalContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            terminal: session.terminal,
            controller: _controller,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: RecordButton(session: session),
        ),
      ],
    );
  }

  Widget _statusView(IconData icon, String message, Color color) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(
                    color: color, fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onRestart,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Restart shell'),
            ),
          ],
        ),
      ),
    );
  }
}
