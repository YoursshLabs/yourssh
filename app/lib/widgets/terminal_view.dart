import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/ssh_session.dart';
import '../providers/command_history_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../theme/terminal_themes.dart';
import 'command_gutter.dart';
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
      SessionStatus.connected => _TerminalWidget(key: ValueKey(session.id), session: session),
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
  const _TerminalWidget({super.key, required this.session});

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
    if (!mounted) return;
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
    if (_matches.isEmpty) return;
    _scrollToLine(_matches[matchIdx].lineIdx);
  }

  /// xterm forces TextStyle.height = 1.2, so each rendered line is
  /// `fontSize * 1.2` pixels tall — the unit the scroll offset is measured in.
  double get _lineHeightPx => context.read<SettingsProvider>().fontSize * 1.2;

  /// Animate the viewport so [line] (an absolute buffer line) is at the top.
  void _scrollToLine(int line) {
    if (!_scrollController.hasClients) return;
    final offset = (line * _lineHeightPx)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  /// Scroll to the previous (-1) or next (+1) command prompt line. Returns true
  /// only if a jump actually occurred, so the key handler can let the key fall
  /// through to the terminal when there is nothing to jump to.
  bool _jumpToPrompt(int direction) {
    final st = context
        .read<ShellIntegrationProvider>()
        .maybeStateFor(widget.session.id);
    if (st == null || st.commands.isEmpty || !_scrollController.hasClients) {
      return false;
    }
    final currentLine = _scrollController.offset / _lineHeightPx;
    final lines = st.commands.map((c) => c.promptLine).toList()..sort();
    int? target;
    if (direction < 0) {
      for (final l in lines) {
        if (l < currentLine - 0.5) target = l;
      }
    } else {
      for (final l in lines) {
        if (l > currentLine + 0.5) {
          target = l;
          break;
        }
      }
    }
    if (target == null) return false;
    _scrollToLine(target);
    return true;
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

    // Open search (Cmd+F on macOS, Ctrl+F elsewhere)
    if ((meta || ctrl) && key == LogicalKeyboardKey.keyF) {
      setState(() => _searchVisible = true);
      return KeyEventResult.handled;
    }

    // While search bar is visible: intercept Escape and Enter only;
    // all other keys flow to the TextField via its own focus.
    if (_searchVisible) {
      if (key == LogicalKeyboardKey.escape) {
        _closeSearch();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _goPrev();
        } else {
          _goNext();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Jump-to-prompt (Cmd+↑/↓ on macOS, Ctrl+↑/↓ elsewhere). Only swallow the
    // key when a jump actually happened — otherwise let it reach the terminal
    // (e.g. Ctrl+↑/↓ word navigation), so non-integration sessions are unaffected.
    final jumpMod = Platform.isMacOS ? meta : ctrl;
    if (jumpMod && key == LogicalKeyboardKey.arrowUp) {
      if (_jumpToPrompt(-1)) return KeyEventResult.handled;
    }
    if (jumpMod && key == LogicalKeyboardKey.arrowDown) {
      if (_jumpToPrompt(1)) return KeyEventResult.handled;
    }

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
    final showGutter = settings.shellIntegrationEnabled &&
        widget.session.host.shellIntegration;

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
          // Leave room for the gutter so it never occludes column-0 text.
          padding: showGutter ? const EdgeInsets.only(left: 10) : EdgeInsets.zero,
          autofocus: !_searchVisible,
          onKeyEvent: _handleKey,
        ),
        if (showGutter)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: CommandGutter(
              sessionId: widget.session.id,
              scrollController: _scrollController,
              lineHeight: settings.fontSize * 1.2,
              onJumpTo: _scrollToLine,
            ),
          ),
        if (_searchVisible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _SearchBar(
              controller: _searchTextController,
              useRegex: _searchRegex,
              hasError: _searchError,
              matchCount: _matches.length,
              currentMatch: _currentMatch,
              onQueryChanged: (q) {
                _searchQuery = q;
                _runSearch();
              },
              onToggleRegex: () {
                setState(() => _searchRegex = !_searchRegex);
                _runSearch();
              },
              onNext: _goNext,
              onPrev: _goPrev,
              onClose: _closeSearch,
            ),
          ),
        Positioned(
          top: _searchVisible ? 44 : 8,
          right: 8,
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

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool useRegex;
  final bool hasError;
  final int matchCount;
  final int currentMatch;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleRegex;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  const _SearchBar({
    required this.controller,
    required this.useRegex,
    required this.hasError,
    required this.matchCount,
    required this.currentMatch,
    required this.onQueryChanged,
    required this.onToggleRegex,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasResults = matchCount > 0;
    final countLabel = controller.text.isEmpty
        ? ''
        : hasError
            ? 'Invalid regex'
            : hasResults
                ? '${currentMatch + 1} of $matchCount'
                : 'No results';
    final countColor = hasError
        ? Colors.red
        : hasResults
            ? const Color(0xFF888888)
            : Colors.orange;

    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onQueryChanged,
              style: const TextStyle(
                color: Color(0xFFEEEEEE),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: useRegex ? 'Search (regex)…' : 'Search…',
                hintStyle:
                    const TextStyle(color: Color(0xFF555555), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (countLabel.isNotEmpty)
            Text(
              countLabel,
              style: TextStyle(
                color: countColor,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          const SizedBox(width: 8),
          _SearchBtn(
            tooltip: 'Use regex',
            active: useRegex,
            label: '.*',
            onTap: onToggleRegex,
          ),
          const SizedBox(width: 4),
          _SearchBtn(
            tooltip: 'Previous match (Shift+Enter)',
            icon: Icons.keyboard_arrow_up,
            onTap: onPrev,
          ),
          const SizedBox(width: 2),
          _SearchBtn(
            tooltip: 'Next match (Enter)',
            icon: Icons.keyboard_arrow_down,
            onTap: onNext,
          ),
          const SizedBox(width: 4),
          _SearchBtn(
            tooltip: 'Close search (Escape)',
            icon: Icons.close,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _SearchBtn extends StatefulWidget {
  final String? tooltip;
  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const _SearchBtn({
    this.tooltip,
    this.label,
    this.icon,
    this.active = false,
    required this.onTap,
  }) : assert(label != null || icon != null);

  @override
  State<_SearchBtn> createState() => _SearchBtnState();
}

class _SearchBtnState extends State<_SearchBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? const Color(0xFF4FC3F7)
        : _hovered
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666);

    final child = widget.label != null
        ? Text(
            widget.label!,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600),
          )
        : Icon(widget.icon, size: 14, color: color);

    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.active
                  ? const Color(0xFF4FC3F7).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
