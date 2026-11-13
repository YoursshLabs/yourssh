import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/local_session.dart';
import '../providers/settings_provider.dart';
import '../theme/terminal_themes.dart';
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
          FLucideIcons.circleAlert,
          session.errorMessage ?? 'Failed to start shell',
          YsColors.error,
        ),
      LocalSessionStatus.exited => _statusView(
          FLucideIcons.unplug, 'Shell exited', YsColors.mutedForeground),
      LocalSessionStatus.running => _terminal(context),
    };
  }

  Widget _terminal(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final keywordRules = settings.xtermKeywordRules;
    return Stack(
      children: [
        TerminalView(
          key: ValueKey(session.id),
          session.terminal,
          controller: _controller,
          autofocus: true,
          keywordRules: keywordRules,
          // Local shells have no host, so only the global appearance applies.
          theme: terminalThemeByName(settings.terminalTheme),
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
    return ColoredBox(
      color: YsColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(YsSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 40),
              const SizedBox(height: YsSpace.s3),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: YsSpace.s4),
              FButton(
                variant: .outline,
                size: .sm,
                mainAxisSize: MainAxisSize.min,
                onPress: widget.onRestart,
                prefix: const Icon(FLucideIcons.refreshCw),
                child: const Text('Restart shell'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
