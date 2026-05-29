import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/command_history_provider.dart';

class TerminalInputBar extends StatefulWidget {
  final String sessionId;
  final void Function(String command) onSubmit;
  final VoidCallback onDismiss;

  const TerminalInputBar({
    super.key,
    required this.sessionId,
    required this.onSubmit,
    required this.onDismiss,
  });

  @override
  State<TerminalInputBar> createState() => _TerminalInputBarState();
}

class _TerminalInputBarState extends State<TerminalInputBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final provider = context.read<CommandHistoryProvider>();
    setState(() {
      _suggestions = provider.suggestions(widget.sessionId, _controller.text);
    });
  }

  void _submit(String command) {
    if (command.trim().isEmpty) return;
    context.read<CommandHistoryProvider>().recordCommand(widget.sessionId, command);
    widget.onSubmit('$command\n');
    _controller.clear();
    setState(() => _suggestions = []);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final provider = context.read<CommandHistoryProvider>();
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final cmd = provider.navigateUp(widget.sessionId);
      if (cmd != null) _controller.text = cmd;
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final cmd = provider.navigateDown(widget.sessionId);
      _controller.text = cmd ?? '';
      return KeyEventResult.handled;
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
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => _submit(_suggestions[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    _suggestions[i],
                    style: const TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Focus(
          focusNode: _focus,
          onKeyEvent: _handleKey,
          child: TextField(
            controller: _controller,
            style: const TextStyle(
              color: Color(0xFFD4D4D4),
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF141414),
              hintText: 'Type command… (↑↓ history, Esc dismiss)',
              hintStyle: const TextStyle(color: Color(0xFF555555)),
              border: const OutlineInputBorder(borderSide: BorderSide.none),
              prefixIcon: const Icon(Icons.terminal, color: Color(0xFF22C55E), size: 16),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: _submit,
          ),
        ),
      ],
    );
  }
}
