import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/host.dart';
import '../models/ssh_session.dart';
import '../providers/command_history_provider.dart';
import '../providers/host_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../services/hotkey_service.dart';
import '../theme/terminal_themes.dart';
import '../util/terminal_appearance.dart';
import 'command_gutter.dart';
import 'record_button.dart';
import 'session_connecting_view.dart';
import 'suggestion_popup.dart';
import 'terminal_context_menu.dart';

class SessionTerminalView extends StatelessWidget {
  final SshSession session;
  const SessionTerminalView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.status == SessionStatus.connected) {
      return _TerminalWidget(key: ValueKey(session.id), session: session);
    }
    final sessions = context.read<SessionProvider>();
    return SessionConnectingView(
      session: session,
      onClose: () => sessions.closeSession(session.id),
      onRetry: () => sessions.reconnectSession(session.id),
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

  /// The terminal's focus (handed back when the search closes) and the
  /// search field's (focused when the search opens, so the query is typed
  /// into the field and never reaches the shell).
  final _terminalFocus = FocusNode();
  final _searchFocus = FocusNode();

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
    _terminalFocus.dispose();
    _searchFocus.dispose();
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

    final termTheme = terminalThemeByName(_appearance(watch: false).themeName);

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

  /// Per-host appearance resolved against globals. The fresh host is looked
  /// up by id — the session's Host snapshot goes stale after copyWith (same
  /// pattern as SessionTab). HostProvider can be absent in widget tests →
  /// fall back to the snapshot.
  TerminalAppearance _appearance({required bool watch}) {
    final settings = watch
        ? context.watch<SettingsProvider>()
        : context.read<SettingsProvider>();
    Host? fresh;
    try {
      if (watch) {
        // select, not watch: rebuild only when THIS host's appearance
        // fields change — a plain watch would rebuild every open terminal
        // on any host-list mutation (e.g. each dashboard-search keystroke).
        context.select<HostProvider, (String?, String?, double?)>((p) {
          final h = p.byId(widget.session.host.id);
          return (h?.terminalThemeId, h?.fontFamily, h?.fontSize);
        });
      }
      fresh = context.read<HostProvider>().byId(widget.session.host.id);
    } on ProviderNotFoundException {
      // Tests pump this widget without a HostProvider.
    }
    return resolveTerminalAppearance(
      host: fresh ?? widget.session.host,
      globalTheme: settings.terminalTheme,
      globalFont: settings.terminalFont,
      globalFontSize: settings.fontSize,
    );
  }

  /// xterm forces TextStyle.height = 1.2, so each rendered line is
  /// `fontSize * 1.2` pixels tall — the unit the scroll offset is measured in.
  double get _lineHeightPx => _appearance(watch: false).fontSize * 1.2;

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
    final termTheme =
        terminalThemeByName(_appearance(watch: false).themeName);
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
    final termTheme =
        terminalThemeByName(_appearance(watch: false).themeName);
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
    _terminalFocus.requestFocus();
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
    // App hotkeys (in-app scope) already fired at the HardwareKeyboard layer;
    // swallow the combo here so it never reaches the shell (issue #46).
    if (HotkeyService().shouldSwallowKeyEvent(event)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;

    // Open search (Cmd+F on macOS, Ctrl+F elsewhere)
    if ((meta || ctrl) && key == LogicalKeyboardKey.keyF) {
      setState(() => _searchVisible = true);
      _searchFocus.requestFocus();
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
    final keywordRules = settings.xtermKeywordRules;
    final appearance = _appearance(watch: true);
    final theme = terminalThemeByName(appearance.themeName);
    final showGutter = settings.shellIntegrationEnabled &&
        widget.session.host.shellIntegration;

    return Stack(
      children: [
        TerminalView(
          widget.session.terminal,
          controller: _controller,
          scrollController: _scrollController,
          focusNode: _terminalFocus,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: appearance.fontSize,
            fontFamily: appearance.fontFamily,
          ),
          // Leave room for the gutter so it never occludes column-0 text.
          padding: showGutter ? const EdgeInsets.only(left: 10) : EdgeInsets.zero,
          autofocus: !_searchVisible,
          keywordRules: keywordRules,
          onKeyEvent: _handleKey,
          onSecondaryTapUp: (details, _) => showTerminalContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            terminal: widget.session.terminal,
            controller: _controller,
          ),
        ),
        if (showGutter)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: CommandGutter(
              sessionId: widget.session.id,
              scrollController: _scrollController,
              lineHeight: appearance.fontSize * 1.2,
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
              focusNode: _searchFocus,
              useRegex: _searchRegex,
              hasError: _searchError,
              matchCount: _matches.length,
              currentMatch: _currentMatch,
              onQueryChanged: (q) {
                // The field reports selection moves too; search on text only.
                if (q == _searchQuery) return;
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
          child: RecordButton(session: widget.session),
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

class _SearchMatch {
  final int lineIdx;
  final int startCol;
  final int endCol;
  const _SearchMatch(this.lineIdx, this.startCol, this.endCol);
}

/// Terminal search strip (Cmd/Ctrl+F): query field, match count, regex
/// toggle, previous / next and close. In the focused field Enter goes to the
/// next match, Shift+Enter to the previous one and Escape closes the search.
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
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
    required this.focusNode,
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

  static const _mono = TextStyle(
    fontFamily: kYsMonoFontFamily,
    fontFamilyFallback: kYsMonoFontFallback,
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      HardwareKeyboard.instance.isShiftPressed ? onPrev() : onNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _button(String tooltip, Widget icon, VoidCallback onPress,
          {bool selected = false}) =>
      Tooltip(
        message: tooltip,
        child: FButton.icon(
          variant: selected ? .secondary : .ghost,
          size: .xs,
          selected: selected,
          onPress: onPress,
          child: icon,
        ),
      );

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
        ? YsColors.error
        : hasResults
            ? YsColors.mutedForeground
            : YsColors.warn;

    // Key handler only, never focusable itself: keys from the focused field
    // bubble up to it.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Container(
        height: 40,
        decoration: const BoxDecoration(
          color: YsColors.card,
          border: Border(bottom: BorderSide(color: YsColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: YsSpace.s2),
        child: Row(
          children: [
            Expanded(
              child: FTextField(
                key: const Key('terminal-search-field'),
                control: FTextFieldControl.managed(
                  controller: controller,
                  onChange: (v) => onQueryChanged(v.text),
                ),
                focusNode: focusNode,
                autofocus: true,
                size: .sm,
                hint: useRegex ? 'Search (regex)…' : 'Search…',
                style: .delta(
                  contentTextStyle: .delta([
                    .base(
                      const .delta(
                        fontFamily: kYsMonoFontFamily,
                        fontFamilyFallback: kYsMonoFontFallback,
                        fontSize: 12,
                      ),
                    ),
                  ]),
                ),
                prefixBuilder: (context, style, variants) =>
                    FTextField.prefixIconBuilder(
                  context,
                  style,
                  variants,
                  const Icon(FLucideIcons.search),
                ),
              ),
            ),
            const SizedBox(width: YsSpace.s2),
            if (countLabel.isNotEmpty)
              Text(
                countLabel,
                key: const Key('terminal-search-count'),
                style: _mono.copyWith(color: countColor, fontSize: 11),
              ),
            const SizedBox(width: YsSpace.s2),
            _button(
              'Use regex',
              Text(
                '.*',
                style: _mono.copyWith(
                  color: useRegex
                      ? YsColors.accentText
                      : YsColors.mutedForeground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onToggleRegex,
              selected: useRegex,
            ),
            _button('Previous match (Shift+Enter)',
                const Icon(FLucideIcons.chevronUp), onPrev),
            _button('Next match (Enter)', const Icon(FLucideIcons.chevronDown),
                onNext),
            _button('Close search (Escape)', const Icon(FLucideIcons.x),
                onClose),
          ],
        ),
      ),
    );
  }
}
