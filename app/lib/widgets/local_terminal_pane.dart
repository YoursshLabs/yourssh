import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';
import '../providers/settings_provider.dart';
import 'record_button.dart';

/// Terminal pane for a local PTY session inside the split terminal workspace.
/// Mirrors SessionTerminalView's status handling, minus SSH-only features
/// (search, shell integration, command gutter).
class LocalTerminalPane extends StatelessWidget {
  final LocalSession session;
  final VoidCallback onRestart;
  const LocalTerminalPane(
      {super.key, required this.session, required this.onRestart});

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
          autofocus: true,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
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
              onPressed: onRestart,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Restart shell'),
            ),
          ],
        ),
      ),
    );
  }
}
