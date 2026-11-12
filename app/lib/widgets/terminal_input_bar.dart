import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/audit_event.dart';
import '../providers/command_history_provider.dart';
import '../providers/session_provider.dart';
import '../services/audit_service.dart';
import '../services/path_completion.dart';
import 'suggestion_popup.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class TerminalInputBar extends StatefulWidget {
  final String sessionId;
  final void Function(String command) onSubmit;
  final VoidCallback onDismiss;

  /// Current shell-integration cwd (null when unknown) — enables cwd-aware
  /// path completion.
  final String? cwd;

  /// Lists a remote directory for path completion. null disables it.
  final Future<List<String>> Function(String dir)? listDir;

  const TerminalInputBar({
    super.key,
    required this.sessionId,
    required this.onSubmit,
    required this.onDismiss,
    this.cwd,
    this.listDir,
  });

  @override
  State<TerminalInputBar> createState() => _TerminalInputBarState();
}

class _TerminalInputBarState extends State<TerminalInputBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<String> _suggestions = [];
  int _selectedIndex = -1;
  Timer? _debounce;
  int _completionSeq = 0;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final text = _controller.text;
    final history = context.read<CommandHistoryProvider>();
    final plan = planPathCompletion(text, widget.cwd);
    if (plan == null || widget.listDir == null) {
      // Invalidate any in-flight path-completion timer so a late result can't
      // overwrite these history suggestions.
      _debounce?.cancel();
      _completionSeq++;
      setState(() {
        _suggestions = history.suggestions(widget.sessionId, text);
        _selectedIndex = -1;
      });
      return;
    }
    // Path completion: list the remote dir (debounced + stale-guarded).
    _debounce?.cancel();
    final seq = ++_completionSeq;
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      final entries = await widget.listDir!(plan.dir);
      if (!mounted || seq != _completionSeq) return; // stale keystroke
      setState(() {
        _suggestions = mergePathSuggestions(text, plan, entries);
        _selectedIndex = -1;
      });
    });
  }

  void _submit(String command) {
    if (command.trim().isEmpty) return;
    context.read<CommandHistoryProvider>().recordCommand(widget.sessionId, command);
    try {
      final audit = context.read<AuditService>();
      final host =
          context.read<SessionProvider>().hostForSession(widget.sessionId);
      audit.record(AuditEvent.now(
        type: AuditEventType.input,
        host: host,
        sessionId: widget.sessionId,
        command: command,
        meta: const {'source': 'input-bar'},
      ));
    } on ProviderNotFoundException {
      // Panes pumped without audit wiring (tests).
    }
    widget.onSubmit('$command\n');
    _controller.clear();
    setState(() {
      _suggestions = [];
      _selectedIndex = -1;
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final provider = context.read<CommandHistoryProvider>();

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_suggestions.isNotEmpty) {
        final completion = _suggestions[max(0, _selectedIndex)];
        _controller.text = completion;
        _controller.selection = TextSelection.collapsed(offset: completion.length);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_suggestions.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1).clamp(-1, _suggestions.length - 1);
        });
      } else {
        final cmd = provider.navigateUp(widget.sessionId);
        if (cmd != null) _controller.text = cmd;
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_suggestions.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1).clamp(-1, _suggestions.length - 1);
        });
      } else {
        final cmd = provider.navigateDown(widget.sessionId);
        _controller.text = cmd ?? '';
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _suggestions.isNotEmpty) {
        _submit(_suggestions[_selectedIndex]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      provider.resetCursor(widget.sessionId);
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: YsColors.card,
        border: Border(top: BorderSide(color: YsColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(YsSpace.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_suggestions.isNotEmpty) ...[
              SuggestionPopup(
                suggestions: _suggestions,
                selectedIndex: _selectedIndex,
                onSelect: _submit,
              ),
              const SizedBox(height: YsSpace.s1),
            ],
            Focus(
              focusNode: _focus,
              onKeyEvent: _handleKey,
              child: FTextField(
                key: const Key('terminal-input-field'),
                control: FTextFieldControl.managed(controller: _controller),
                size: .sm,
                hint:
                    'Type command… (↑↓ history/suggestions, Tab complete, Esc dismiss)',
                style: .delta(
                  contentTextStyle: .delta([
                    .base(
                      const .delta(
                        fontFamily: kYsMonoFontFamily,
                        fontFamilyFallback: kYsMonoFontFallback,
                        fontSize: 13,
                      ),
                    ),
                  ]),
                ),
                prefixBuilder: (context, style, variants) =>
                    FTextField.prefixIconBuilder(
                  context,
                  style,
                  variants,
                  const Icon(FLucideIcons.terminal, color: YsColors.primary),
                ),
                onSubmit: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
