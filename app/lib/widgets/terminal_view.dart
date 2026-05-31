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
  final _controller = TerminalController();
  final _scrollController = ScrollController();

  // Search state
  bool _searchVisible = false;
  String _searchQuery = '';
  bool _searchRegex = false;
  bool _searchError = false;
  List<_SearchMatch> _matches = [];
  int _currentMatch = 0;
  final List<TerminalHighlight> _highlights = [];
  late final TextEditingController _searchTextController;

  String _inputBuffer = '';
  int _selectedIdx = 0;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _searchTextController = TextEditingController();
  }

  void _refreshSuggestions() {
    if (!mounted) return;
    final provider = context.read<CommandHistoryProvider>();
    setState(() {
      _suggestions = provider.suggestions(widget.session.id, _inputBuffer);
      _selectedIdx = 0;
    });
  }

  @override
  void dispose() {
    _clearHighlights();
    _controller.dispose();
    _scrollController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  void _clearHighlights() {
    for (final h in _highlights) {
      h.dispose();
    }
    _highlights.clear();
  }

  void _runSearch() {
    _clearHighlights();

    if (_searchQuery.isEmpty) {
      setState(() {
        _matches = [];
        _currentMatch = 0;
        _searchError = false;
      });
      return;
    }

    RegExp regex;
    try {
      final pattern =
          _searchRegex ? _searchQuery : RegExp.escape(_searchQuery);
      regex = RegExp(pattern, caseSensitive: false);
    } catch (_) {
      setState(() {
        _matches = [];
        _currentMatch = 0;
        _searchError = true;
      });
      return;
    }

    final terminal = widget.session.terminal;
    final buffer = terminal.buffer;
    final lines = terminal.lines;
    final newMatches = <_SearchMatch>[];

    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].getText();
      for (final m in regex.allMatches(text)) {
        newMatches.add(_SearchMatch(i, m.start, m.end));
      }
    }

    final settings = context.read<SettingsProvider>();
    final termTheme = terminalThemeByName(settings.terminalTheme);

    for (var mi = 0; mi < newMatches.length; mi++) {
      final match = newMatches[mi];
      final color = mi == 0
          ? termTheme.searchHitBackgroundCurrent
          : termTheme.searchHitBackground;
      final h = _controller.highlight(
        p1: buffer.createAnchor(match.startCol, match.lineIdx),
        p2: buffer.createAnchor(match.endCol, match.lineIdx),
        color: color,
      );
      _highlights.add(h);
    }

    setState(() {
      _matches = newMatches;
      _currentMatch = 0;
      _searchError = false;
    });

    if (newMatches.isNotEmpty) _scrollToMatch(0);
  }

  void _scrollToMatch(int matchIdx) {
    if (_matches.isEmpty || !_scrollController.hasClients) return;
    final lineIdx = _matches[matchIdx].lineIdx;
    final fontSize = context.read<SettingsProvider>().fontSize;
    final estimatedLineHeight = fontSize * 1.35;
    final offset = (lineIdx * estimatedLineHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _goNext() {
    if (_matches.isEmpty) return;
    final termTheme = terminalThemeByName(
        context.read<SettingsProvider>().terminalTheme);
    final buffer = widget.session.terminal.buffer;

    // Demote current match to normal color
    _highlights[_currentMatch].dispose();
    final old = _matches[_currentMatch];
    _highlights[_currentMatch] = _controller.highlight(
      p1: buffer.createAnchor(old.startCol, old.lineIdx),
      p2: buffer.createAnchor(old.endCol, old.lineIdx),
      color: termTheme.searchHitBackground,
    );

    final next = (_currentMatch + 1) % _matches.length;

    // Promote next match to current color
    _highlights[next].dispose();
    final cur = _matches[next];
    _highlights[next] = _controller.highlight(
      p1: buffer.createAnchor(cur.startCol, cur.lineIdx),
      p2: buffer.createAnchor(cur.endCol, cur.lineIdx),
      color: termTheme.searchHitBackgroundCurrent,
    );

    setState(() => _currentMatch = next);
    _scrollToMatch(next);
  }

  void _goPrev() {
    if (_matches.isEmpty) return;
    final termTheme = terminalThemeByName(
        context.read<SettingsProvider>().terminalTheme);
    final buffer = widget.session.terminal.buffer;

    // Demote current match to normal color
    _highlights[_currentMatch].dispose();
    final old = _matches[_currentMatch];
    _highlights[_currentMatch] = _controller.highlight(
      p1: buffer.createAnchor(old.startCol, old.lineIdx),
      p2: buffer.createAnchor(old.endCol, old.lineIdx),
      color: termTheme.searchHitBackground,
    );

    final prev = (_currentMatch - 1 + _matches.length) % _matches.length;

    // Promote prev match to current color
    _highlights[prev].dispose();
    final cur = _matches[prev];
    _highlights[prev] = _controller.highlight(
      p1: buffer.createAnchor(cur.startCol, cur.lineIdx),
      p2: buffer.createAnchor(cur.endCol, cur.lineIdx),
      color: termTheme.searchHitBackgroundCurrent,
    );

    setState(() => _currentMatch = prev);
    _scrollToMatch(prev);
  }

  void _closeSearch() {
    _clearHighlights();
    _searchTextController.clear();
    setState(() {
      _searchVisible = false;
      _searchQuery = '';
      _searchRegex = false;
      _searchError = false;
      _matches = [];
      _currentMatch = 0;
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
          controller: _controller,
          scrollController: _scrollController,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.terminalFont,
          ),
          padding: EdgeInsets.zero,
          autofocus: !_searchVisible,
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

class _SearchMatch {
  final int lineIdx;
  final int startCol;
  final int endCol;
  const _SearchMatch(this.lineIdx, this.startCol, this.endCol);
}
