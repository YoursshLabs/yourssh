# Shell Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add history-based autocomplete to both the `TerminalInputBar` overlay and the raw xterm terminal, with Tab key completion and arrow key navigation through suggestions.

**Architecture:** A new shared `SuggestionPopup` widget renders the suggestion list in both contexts. `TerminalInputBar` gains Tab/arrow keyboard navigation over its existing history suggestions. `_TerminalWidget` is converted to a `StatefulWidget` that intercepts keystrokes to track a shadow input buffer, then overlays `SuggestionPopup` via `Stack`.

**Tech Stack:** Flutter, `xterm` package (already used), `CommandHistoryProvider` (already exists), `provider` package.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/widgets/suggestion_popup.dart` | Create | Reusable suggestion list widget |
| `app/test/widgets/suggestion_popup_test.dart` | Create | Widget tests for SuggestionPopup |
| `app/lib/widgets/terminal_input_bar.dart` | Modify | Add Tab key + arrow navigation |
| `app/test/widgets/terminal_input_bar_test.dart` | Create | Tests for keyboard navigation |
| `app/lib/widgets/terminal_view.dart` | Modify | StatefulWidget + keystroke tracking + overlay |

---

## Task 1: Create SuggestionPopup widget

**Files:**
- Create: `app/lib/widgets/suggestion_popup.dart`
- Create: `app/test/widgets/suggestion_popup_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/suggestion_popup_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/suggestion_popup.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('SuggestionPopup', () {
    testWidgets('renders all suggestions (up to 8)', (tester) async {
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: ['git status', 'git log', 'git diff'],
        selectedIndex: -1,
        onSelect: (_) {},
      )));
      expect(find.text('git status'), findsOneWidget);
      expect(find.text('git log'), findsOneWidget);
      expect(find.text('git diff'), findsOneWidget);
    });

    testWidgets('caps display at 8 items', (tester) async {
      final cmds = List.generate(10, (i) => 'cmd$i');
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: cmds,
        selectedIndex: -1,
        onSelect: (_) {},
      )));
      for (int i = 0; i < 8; i++) {
        expect(find.text('cmd$i'), findsOneWidget);
      }
      expect(find.text('cmd8'), findsNothing);
      expect(find.text('cmd9'), findsNothing);
    });

    testWidgets('calls onSelect when item tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: ['git status', 'git log'],
        selectedIndex: -1,
        onSelect: (s) => selected = s,
      )));
      await tester.tap(find.text('git log'));
      expect(selected, 'git log');
    });

    testWidgets('selected item has blue background', (tester) async {
      await tester.pumpWidget(wrap(SuggestionPopup(
        suggestions: ['git status', 'git log'],
        selectedIndex: 0,
        onSelect: (_) {},
      )));
      // First item container should have selectedBg color
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final d = c.decoration;
        if (d is BoxDecoration) {
          return d.color == const Color(0xFF1E3A5F);
        }
        return false;
      });
      expect(containers.length, 1);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd app && flutter test test/widgets/suggestion_popup_test.dart
```

Expected: FAIL — `suggestion_popup.dart` not found / `SuggestionPopup` undefined.

- [ ] **Step 3: Implement SuggestionPopup**

Create `app/lib/widgets/suggestion_popup.dart`:

```dart
import 'package:flutter/material.dart';

class SuggestionPopup extends StatelessWidget {
  final List<String> suggestions;
  final int selectedIndex;
  final void Function(String) onSelect;
  final double maxHeight;

  const SuggestionPopup({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelect,
    this.maxHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    final items = suggestions.take(8).toList();
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (_, i) {
          final selected = i == selectedIndex;
          return InkWell(
            onTap: () => onSelect(items[i]),
            child: Container(
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1E3A5F) : Colors.transparent,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                items[i],
                style: TextStyle(
                  color: selected ? const Color(0xFF7DD3FC) : const Color(0xFFD4D4D4),
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd app && flutter test test/widgets/suggestion_popup_test.dart
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/suggestion_popup.dart app/test/widgets/suggestion_popup_test.dart
git commit -m "feat: add SuggestionPopup widget with selection highlight"
```

---

## Task 2: Enhance TerminalInputBar with Tab + arrow keyboard navigation

**Files:**
- Modify: `app/lib/widgets/terminal_input_bar.dart`
- Create: `app/test/widgets/terminal_input_bar_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/terminal_input_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/widgets/terminal_input_bar.dart';

void main() {
  late CommandHistoryProvider historyProvider;

  setUp(() {
    historyProvider = CommandHistoryProvider();
    historyProvider.recordCommand('session1', 'git status');
    historyProvider.recordCommand('session1', 'git log');
    historyProvider.recordCommand('session1', 'git diff');
  });

  Widget wrap({
    required String sessionId,
    required void Function(String) onSubmit,
    VoidCallback? onDismiss,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<CommandHistoryProvider>.value(
          value: historyProvider,
          child: TerminalInputBar(
            sessionId: sessionId,
            onSubmit: onSubmit,
            onDismiss: onDismiss ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('Tab key completes first suggestion into input field', (tester) async {
    String? submitted;
    await tester.pumpWidget(wrap(
      sessionId: 'session1',
      onSubmit: (cmd) => submitted = cmd,
    ));

    // Type 'git' to get suggestions
    await tester.enterText(find.byType(TextField), 'git');
    await tester.pump();

    // Suggestions should appear
    expect(find.text('git diff'), findsOneWidget);

    // Press Tab
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    // Input should be completed, not submitted
    expect(submitted, isNull);
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text, isNotEmpty);
    expect(tf.controller!.text.startsWith('git'), isTrue);
  });

  testWidgets('ArrowDown navigates suggestion list when visible', (tester) async {
    await tester.pumpWidget(wrap(
      sessionId: 'session1',
      onSubmit: (_) {},
    ));

    await tester.enterText(find.byType(TextField), 'git');
    await tester.pump();

    // Suggestions visible — ArrowDown should move selection down
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // Selected item should be highlighted (blue background present)
    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == const Color(0xFF1E3A5F);
    });
    expect(containers.length, greaterThanOrEqualTo(1));
  });

  testWidgets('Tab with no suggestions inserts nothing and does not submit', (tester) async {
    String? submitted;
    await tester.pumpWidget(wrap(
      sessionId: 'session1',
      onSubmit: (cmd) => submitted = cmd,
    ));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    // No suggestions
    expect(find.text('git status'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(submitted, isNull);
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.controller!.text, 'zzz');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd app && flutter test test/widgets/terminal_input_bar_test.dart
```

Expected: FAIL — Tab key not handled, `_selectedIndex` not defined.

- [ ] **Step 3: Implement TerminalInputBar changes**

Replace the full contents of `app/lib/widgets/terminal_input_bar.dart`:

```dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/command_history_provider.dart';
import 'suggestion_popup.dart';

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
  int _selectedIndex = -1;

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
      _selectedIndex = -1;
    });
  }

  void _submit(String command) {
    if (command.trim().isEmpty) return;
    context.read<CommandHistoryProvider>().recordCommand(widget.sessionId, command);
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
          SuggestionPopup(
            suggestions: _suggestions,
            selectedIndex: _selectedIndex,
            onSelect: _submit,
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
              hintText: 'Type command… (↑↓ history/suggestions, Tab complete, Esc dismiss)',
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/widgets/terminal_input_bar_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
cd app && flutter test
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/terminal_input_bar.dart app/test/widgets/terminal_input_bar_test.dart
git commit -m "feat: add Tab completion and arrow key navigation to TerminalInputBar"
```

---

## Task 3: Convert _TerminalWidget to StatefulWidget with autocomplete overlay

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

Note: `_TerminalWidget` is a private class inside `terminal_view.dart`. Widget tests for it must pump `SessionTerminalView` with a real or fake `SshSession`. Since `SshSession` wraps xterm's `Terminal`, we test via a thin smoke test that the `Stack` structure renders — functional verification is done manually in the running app.

- [ ] **Step 1: Write a smoke test**

Add to `app/test/widgets/suggestion_popup_test.dart` (append a new group at the bottom):

```dart
// Add this import at the top of suggestion_popup_test.dart
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/widgets/terminal_view.dart';
import 'package:provider/provider.dart';

// Add this group inside main() after existing groups:
group('SessionTerminalView autocomplete overlay', () {
  testWidgets('renders without error when connected', (tester) async {
    final session = SshSession(
      host: Host(label: 'test', host: 'localhost', port: 22, username: 'root'),
    );
    session.markConnected();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SessionTerminalView(session: session),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SessionTerminalView), findsOneWidget);
  });
});
```

- [ ] **Step 2: Run to confirm it passes before changes**

```bash
cd app && flutter test test/widgets/suggestion_popup_test.dart
```

Expected: PASS (existing tests) + new smoke test PASS.

- [ ] **Step 3: Implement _TerminalWidget as StatefulWidget**

Replace the `_TerminalWidget` class in `app/lib/widgets/terminal_view.dart` (leave all theme constants and `SessionTerminalView` unchanged). Add the import at the top and replace the class:

Add imports at the top (after existing imports):
```dart
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/command_history_provider.dart';
import 'suggestion_popup.dart';
```

Replace the `_TerminalWidget` class (lines 38–68 of original file):

```dart
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
      setState(() { _inputBuffer = ''; _suggestions = []; });
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.backspace) {
      if (_inputBuffer.isNotEmpty) {
        setState(() => _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1));
        _refreshSuggestions();
      }
      return KeyEventResult.ignored;
    }

    // Track printable single characters (no ctrl/meta modifier)
    if (!ctrl && !meta) {
      final char = event.character;
      if (char != null && char.length == 1) {
        _inputBuffer += char;
        _refreshSuggestions();
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = _themeFor(settings.terminalTheme);

    return Stack(
      children: [
        Focus(
          onKeyEvent: _handleKey,
          child: TerminalView(
            widget.session.terminal,
            theme: theme,
            textStyle: TerminalStyle(
              fontSize: settings.fontSize,
              fontFamily: settings.terminalFont,
            ),
            padding: EdgeInsets.zero,
            autofocus: true,
          ),
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
```

- [ ] **Step 4: Run smoke test and full suite**

```bash
cd app && flutter test
```

Expected: All tests PASS. If `markConnected()` doesn't exist on `SshSession`, check the actual method name via `grep -n "connected\|markConnected\|status" app/lib/models/ssh_session.dart` and update the smoke test accordingly.

- [ ] **Step 5: Run flutter analyze**

```bash
cd app && flutter analyze
```

Expected: No new errors or warnings.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/terminal_view.dart app/test/widgets/suggestion_popup_test.dart
git commit -m "feat: add keystroke-tracked autocomplete overlay to raw xterm terminal"
```

---

## Task 4: Manual verification

- [ ] **Step 1: Run the app**

```bash
cd app && flutter run -d macos
```

- [ ] **Step 2: Verify TerminalInputBar autocomplete**

1. Connect to any SSH host.
2. Run a few commands (e.g. `ls`, `git status`, `pwd`).
3. Press the input bar hotkey to show `TerminalInputBar`.
4. Type `gi` — suggestions list should appear with matching history items highlighted.
5. Press `↓` — second suggestion highlights in blue.
6. Press `Tab` — input field fills with selected suggestion (not submitted).
7. Press `Enter` — command executes.
8. Press `↑` with no prefix — history navigation still works.

- [ ] **Step 3: Verify raw xterm autocomplete**

1. In the raw terminal (not the input bar), type a prefix that matches a history command (e.g. `gi`).
2. Suggestion popup appears at bottom-right of the terminal pane.
3. Press `↓` to navigate, `Tab` to complete — the command text appears at the shell prompt.
4. Press `Enter` twice to reset buffer — popup disappears.
5. Press `Tab` with no suggestion — shell's own tab completion fires (path/binary completion works normally).

- [ ] **Step 4: Commit if everything looks good**

```bash
git add -p  # review any last changes
git commit -m "chore: verify shell autocomplete feature complete"
```
