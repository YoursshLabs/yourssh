import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/ssh_session.dart';
import '../providers/command_history_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/terminal_themes.dart';
import 'suggestion_popup.dart';

class SessionTerminalView extends StatelessWidget {
  final SshSession session;
  const SessionTerminalView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return switch (session.status) {
      SessionStatus.connecting => _statusView(Icons.sync, 'Connecting to ${session.host.host}…', Colors.orange),
      SessionStatus.error => _statusView(Icons.error_outline, session.errorMessage ?? 'Connection error', Colors.red),
      SessionStatus.disconnected => _statusView(Icons.link_off, 'Disconnected', Colors.grey),
      SessionStatus.connected => _TerminalWidget(session: session),
    };
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
            Text(message, style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _TerminalWidget extends StatefulWidget {
  final SshSession session;
  const _TerminalWidget({required this.session});

  @override
  State<_TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<_TerminalWidget> {
  String _inputBuffer = '';
  int _selectedIdx = 0;
  List<String> _suggestions = [];

  void _refreshSuggestions() {
    if (!mounted) return;
    final provider = context.read<CommandHistoryProvider>();
    setState(() {
      _suggestions = provider.suggestions(widget.session.id, _inputBuffer);
      _selectedIdx = 0;
    });
  }

  void _completeTo(String suggestion) {
    widget.session.terminal.textInput('\b' * _inputBuffer.length);
    widget.session.terminal.textInput(suggestion);
    setState(() {
      _inputBuffer = suggestion;
      _suggestions = [];
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;

    if (key == LogicalKeyboardKey.tab) {
      if (_suggestions.isNotEmpty) {
        _completeTo(_suggestions[_selectedIdx]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _selectedIdx = (_selectedIdx - 1).clamp(0, _suggestions.length - 1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _selectedIdx = (_selectedIdx + 1).clamp(0, _suggestions.length - 1));
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.enter ||
        (ctrl && key == LogicalKeyboardKey.keyC) ||
        (ctrl && key == LogicalKeyboardKey.keyU)) {
      setState(() {
        _inputBuffer = '';
        _suggestions = [];
      });
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.backspace) {
      if (_inputBuffer.isNotEmpty) {
        setState(() => _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1));
        _refreshSuggestions();
      }
      return KeyEventResult.ignored;
    }

    if (!ctrl && !meta) {
      final char = event.character;
      if (char != null && char.length == 1 && char.codeUnitAt(0) >= 0x20) {
        _inputBuffer += char;
        _refreshSuggestions();
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = terminalThemeByName(settings.terminalTheme);

    return Stack(
      children: [
        TerminalView(
          widget.session.terminal,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
          padding: EdgeInsets.zero,
          autofocus: true,
          onKeyEvent: _handleKey,
        ),
        Positioned(
          top: 8,
          left: 8,
          child: _RecordButton(session: widget.session),
        ),
        if (_suggestions.isNotEmpty)
          Positioned(
            bottom: 8,
            right: 8,
            width: 320,
            child: SuggestionPopup(
              suggestions: _suggestions,
              selectedIndex: _selectedIdx,
              onSelect: _completeTo,
            ),
          ),
      ],
    );
  }

}

class _RecordButton extends StatelessWidget {
  final SshSession session;
  const _RecordButton({required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final isRecording = provider.isRecording(session.id);

    return Tooltip(
      message: isRecording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: () {
          if (isRecording) {
            provider.stopRecording(session.id);
          } else {
            provider.startRecording(session);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isRecording ? Colors.red.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRecording ? Icons.stop_circle_outlined : Icons.fiber_manual_record,
                size: 12,
                color: isRecording ? Colors.red : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'REC',
                style: TextStyle(
                  color: isRecording ? Colors.red : Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
