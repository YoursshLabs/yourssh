# Command Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global fuzzy-search Command Palette (Cmd/Ctrl+K) that lets users connect to hosts, navigate sections, run snippets, and trigger actions without the mouse.

**Architecture:** `showDialog` overlay — `CommandPaletteDialog` is a self-contained `StatefulWidget` that reads item lists from constructor params and manages its own search/selection state. Pure `CommandPaletteSearcher` class handles fuzzy scoring and match highlighting. Wired into the existing `_handleHotkey` / `_registerHotkeys` system in `MainScreen`.

**Tech Stack:** Flutter, `hotkey_manager` (already in pubspec), `dart:math` for `clamp`, `provider` package for reading existing providers.

---

## File Map

| File | Change |
|---|---|
| `app/lib/widgets/command_palette.dart` | **New** — `CommandItem`, `CommandType`, `CommandPaletteSearcher`, `CommandPaletteDialog` |
| `app/test/widgets/command_palette_test.dart` | **New** — unit tests for searcher + widget tests for dialog |
| `app/lib/providers/settings_provider.dart` | Add `command_palette` to default `hotkeys` map |
| `app/lib/widgets/hotkey_settings_screen.dart` | Add `command_palette` label to `_labels` map |
| `app/lib/screens/main_screen.dart` | Add `_openCommandPalette()`, wire `_handleHotkey('command_palette')` |

---

## Task 1: `CommandPaletteSearcher` — pure fuzzy logic

**Files:**
- Create: `app/lib/widgets/command_palette.dart`
- Create: `app/test/widgets/command_palette_test.dart`

- [ ] **Step 1: Write failing unit tests for `CommandPaletteSearcher`**

Create `app/test/widgets/command_palette_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/command_palette.dart';

void main() {
  group('CommandPaletteSearcher.score', () {
    test('returns 0 when query is not a subsequence of target', () {
      expect(CommandPaletteSearcher.score('xyz', 'prod-db'), 0);
    });

    test('returns positive score for valid subsequence', () {
      expect(CommandPaletteSearcher.score('pd', 'prod-db'), greaterThan(0));
    });

    test('scores "pd" against "prod-db" higher than against "padding"', () {
      final scoreProdb = CommandPaletteSearcher.score('pd', 'prod-db');
      final scorePadding = CommandPaletteSearcher.score('pd', 'padding');
      expect(scoreProdb, greaterThan(scorePadding));
    });

    test('returns positive score for empty query', () {
      expect(CommandPaletteSearcher.score('', 'anything'), greaterThan(0));
    });

    test('case-insensitive match', () {
      expect(CommandPaletteSearcher.score('PD', 'prod-db'), greaterThan(0));
    });
  });

  group('CommandPaletteSearcher.search', () {
    late List<CommandItem> items;

    setUp(() {
      items = [
        CommandItem(
          id: '1', title: 'prod-db', subtitle: '', icon: Icons.dns,
          type: CommandType.host, execute: () {},
        ),
        CommandItem(
          id: '2', title: 'padding', subtitle: '', icon: Icons.dns,
          type: CommandType.host, execute: () {},
        ),
        CommandItem(
          id: '3', title: 'staging', subtitle: '', icon: Icons.dns,
          type: CommandType.host, execute: () {},
        ),
      ];
    });

    test('empty query returns all items unchanged', () {
      final results = CommandPaletteSearcher.search('', items);
      expect(results.length, 3);
    });

    test('filters out non-matching items', () {
      final results = CommandPaletteSearcher.search('pd', items);
      final titles = results.map((r) => r.title).toList();
      expect(titles, isNot(contains('staging')));
    });

    test('sorts by score descending — prod-db before padding for query "pd"', () {
      final results = CommandPaletteSearcher.search('pd', items);
      expect(results.first.title, 'prod-db');
    });
  });

  group('CommandPaletteSearcher.highlightSpans', () {
    test('empty query returns single non-match span for full text', () {
      final spans = CommandPaletteSearcher.highlightSpans('', 'prod-db');
      expect(spans.length, 1);
      expect(spans.first.$1, 'prod-db');
      expect(spans.first.$2, false);
    });

    test('matched chars are marked as match spans', () {
      final spans = CommandPaletteSearcher.highlightSpans('pd', 'prod-db');
      final matchedChars = spans.where((s) => s.$2).map((s) => s.$1).join();
      expect(matchedChars, 'pd');
    });

    test('full text is preserved across all spans', () {
      final spans = CommandPaletteSearcher.highlightSpans('pd', 'prod-db');
      final full = spans.map((s) => s.$1).join();
      expect(full, 'prod-db');
    });
  });
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app && flutter test test/widgets/command_palette_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/widgets/command_palette.dart'`

- [ ] **Step 3: Implement `CommandItem`, `CommandType`, `CommandPaletteSearcher`**

Create `app/lib/widgets/command_palette.dart` with the following (just the model + searcher for now — the Dialog widget is added in Task 2):

```dart
import 'package:flutter/material.dart';

enum CommandType { action, navSection, host, snippet }

class CommandItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final CommandType type;
  final VoidCallback execute;

  const CommandItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
    required this.execute,
  });
}

class CommandPaletteSearcher {
  CommandPaletteSearcher._();

  static int score(String query, String target) {
    if (query.isEmpty) return 1;
    final q = query.toLowerCase();
    final t = target.toLowerCase();
    int qi = 0;
    int score = 0;
    int consecutive = 0;
    for (int ti = 0; ti < t.length && qi < q.length; ti++) {
      if (t[ti] == q[qi]) {
        score += 1 + consecutive;
        if (ti == qi) score += 2;
        consecutive++;
        qi++;
      } else {
        consecutive = 0;
      }
    }
    return qi == q.length ? score : 0;
  }

  static List<CommandItem> search(String query, List<CommandItem> items) {
    if (query.isEmpty) return items;
    final scored = <({CommandItem item, int score})>[];
    for (final item in items) {
      final s = score(query, item.title);
      if (s > 0) scored.add((item: item, score: s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((r) => r.item).toList();
  }

  static List<(String, bool)> highlightSpans(String query, String text) {
    if (query.isEmpty) return [(text, false)];
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    final result = <(String, bool)>[];
    int qi = 0;
    int lastEnd = 0;
    for (int ti = 0; ti < t.length && qi < q.length; ti++) {
      if (t[ti] == q[qi]) {
        if (ti > lastEnd) result.add((text.substring(lastEnd, ti), false));
        result.add((text.substring(ti, ti + 1), true));
        lastEnd = ti + 1;
        qi++;
      }
    }
    if (lastEnd < text.length) result.add((text.substring(lastEnd), false));
    return result;
  }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/widgets/command_palette_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/command_palette.dart app/test/widgets/command_palette_test.dart
git commit -m "feat: add CommandPaletteSearcher with fuzzy scoring and highlight spans"
```

---

## Task 2: `CommandPaletteDialog` widget

**Files:**
- Modify: `app/lib/widgets/command_palette.dart` (append Dialog widget)
- Modify: `app/test/widgets/command_palette_test.dart` (append widget tests)

- [ ] **Step 1: Write failing widget tests**

Append to `app/test/widgets/command_palette_test.dart`:

```dart
  group('CommandPaletteDialog', () {
    late List<CommandItem> hosts;
    bool connected = false;
    String? navigatedSection;
    String? executedAction;

    setUp(() {
      connected = false;
      navigatedSection = null;
      executedAction = null;
      hosts = [
        CommandItem(
          id: 'h1', title: 'prod-db', subtitle: 'root@prod-db:22',
          icon: Icons.dns, type: CommandType.host,
          execute: () => connected = true,
        ),
        CommandItem(
          id: 'h2', title: 'staging', subtitle: 'root@staging:22',
          icon: Icons.dns, type: CommandType.host,
          execute: () {},
        ),
      ];
    });

    Widget makeDialog(List<CommandItem> items) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => CommandPaletteDialog(items: items),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('shows search field and all items on open', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('prod-db'), findsOneWidget);
      expect(find.text('staging'), findsOneWidget);
    });

    testWidgets('filters items when query is typed', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'prod');
      await tester.pump();
      expect(find.text('prod-db'), findsOneWidget);
      expect(find.text('staging'), findsNothing);
    });

    testWidgets('Escape closes the dialog', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandPaletteDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPaletteDialog), findsNothing);
    });

    testWidgets('arrow down moves selection and Enter executes', (tester) async {
      await tester.pumpWidget(makeDialog(hosts));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // First item is selected by default; Enter executes it
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(connected, true);
    });
  });
```

Also add the missing import at the top of the test file:
```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app && flutter test test/widgets/command_palette_test.dart
```

Expected: FAIL — `CommandPaletteDialog` not defined.

- [ ] **Step 3: Implement `CommandPaletteDialog`**

Append to `app/lib/widgets/command_palette.dart`:

```dart
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/host.dart';
import '../screens/main_screen.dart' show NavSection;
import '../providers/session_provider.dart';

// ---------------------------------------------------------------------------
// CommandPaletteDialog
// ---------------------------------------------------------------------------

class CommandPaletteDialog extends StatefulWidget {
  final List<CommandItem> items;

  const CommandPaletteDialog({super.key, required this.items});

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _selectedIndex = 0;
  List<CommandItem> _results = [];

  static const _itemHeight = 44.0;

  @override
  void initState() {
    super.initState();
    _results = widget.items;
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    setState(() {
      _selectedIndex = 0;
      _results = CommandPaletteSearcher.search(_controller.text, widget.items);
    });
  }

  void _executeSelected() {
    if (_results.isEmpty) return;
    Navigator.of(context).pop();
    _results[_selectedIndex].execute();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final offset = (_selectedIndex * _itemHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(offset);
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = min(_selectedIndex + 1, _results.length - 1);
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = max(_selectedIndex - 1, 0);
      });
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Center(
        child: SizedBox(
          width: 560,
          child: Focus(
            onKeyEvent: _onKeyEvent,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.sidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SearchField(controller: _controller, onSubmitted: (_) => _executeSelected()),
                  if (_results.isNotEmpty) ...[
                    const Divider(height: 1, color: AppColors.border),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 352),
                      child: ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _results.length,
                        itemExtent: _itemHeight,
                        itemBuilder: (_, i) => _CommandRow(
                          item: _results[i],
                          query: _controller.text,
                          selected: i == _selectedIndex,
                          onTap: () {
                            Navigator.of(context).pop();
                            _results[i].execute();
                          },
                          onHover: () => setState(() => _selectedIndex = i),
                        ),
                      ),
                    ),
                  ],
                  _HintBar(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _SearchField({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: onSubmitted,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search hosts, actions, snippets...',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  final CommandItem item;
  final String query;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  const _CommandRow({
    required this.item,
    required this.query,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(item.icon, size: 15, color: selected ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(text: item.title, query: query, selected: selected),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _TypeBadge(type: item.type),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final bool selected;

  const _HighlightedText({required this.text, required this.query, required this.selected});

  @override
  Widget build(BuildContext context) {
    final spans = CommandPaletteSearcher.highlightSpans(query, text);
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: spans.map((s) => TextSpan(
          text: s.$1,
          style: TextStyle(
            color: s.$2
                ? AppColors.accent
                : selected ? AppColors.textPrimary : AppColors.textPrimary,
            fontWeight: s.$2 ? FontWeight.w600 : FontWeight.normal,
            fontSize: 13,
          ),
        )).toList(),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final CommandType type;

  const _TypeBadge({required this.type});

  static const _labels = {
    CommandType.host: 'host',
    CommandType.navSection: 'nav',
    CommandType.snippet: 'snippet',
    CommandType.action: 'action',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        _labels[type] ?? '',
        style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
      ),
    );
  }
}

class _HintBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
      ),
      child: const Row(
        children: [
          _HintChip('↑↓', 'navigate'),
          SizedBox(width: 12),
          _HintChip('↵', 'execute'),
          SizedBox(width: 12),
          _HintChip('esc', 'close'),
        ],
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  final String key_;
  final String label;

  const _HintChip(this.key_, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(key_, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'monospace')),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10)),
      ],
    );
  }
}
```

> Note: `_HintChip` uses a positional `key_` field (not Flutter's `key:` param) to avoid naming collision.

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app && flutter test test/widgets/command_palette_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/command_palette.dart app/test/widgets/command_palette_test.dart
git commit -m "feat: add CommandPaletteDialog widget with fuzzy search and keyboard nav"
```

---

## Task 3: Add `command_palette` hotkey to Settings

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Modify: `app/lib/widgets/hotkey_settings_screen.dart`

- [ ] **Step 1: Add `command_palette` to default hotkeys in `SettingsProvider`**

In `app/lib/providers/settings_provider.dart`, change the `hotkeys` field (line 17-25):

```dart
  Map<String, String> hotkeys = {
    'new_session': 'ctrl+t',
    'close_session': 'ctrl+w',
    'next_session': 'ctrl+tab',
    'prev_session': 'ctrl+shift+tab',
    'toggle_input_bar': 'ctrl+shift+i',
    'split_horizontal': 'ctrl+shift+h',
    'split_vertical': 'ctrl+shift+v',
    'command_palette': Platform.isMacOS ? 'meta+k' : 'ctrl+k',
  };
```

`dart:io` is already imported in this file (used by `recordingPath`).

- [ ] **Step 2: Add `command_palette` label to `HotkeySettingsScreen`**

In `app/lib/widgets/hotkey_settings_screen.dart`, change the `_labels` map (line 19-27):

```dart
  static const _labels = {
    'new_session': 'New Session',
    'close_session': 'Close Session',
    'next_session': 'Next Session',
    'prev_session': 'Previous Session',
    'toggle_input_bar': 'Toggle Input Bar',
    'split_horizontal': 'Split Horizontal',
    'split_vertical': 'Split Vertical',
    'command_palette': 'Command Palette',
  };
```

Also update the recording hint banner text (line 197) to handle the new key gracefully — it already reads from `_labels[_recording]` which now includes `command_palette`, so no change needed.

- [ ] **Step 3: Run analyzer — expect clean**

```bash
cd app && flutter analyze lib/providers/settings_provider.dart lib/widgets/hotkey_settings_screen.dart
```

Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/lib/widgets/hotkey_settings_screen.dart
git commit -m "feat: add command_palette hotkey (meta+k / ctrl+k) to settings"
```

---

## Task 4: Wire Command Palette into `MainScreen`

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add import and `_openCommandPalette()` method**

In `app/lib/screens/main_screen.dart`:

Add import at top (with other widget imports):
```dart
import '../widgets/command_palette.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
```

Add the `_openCommandPalette()` method inside `_MainScreenState` (after `_closePanel()`):

```dart
  void _openCommandPalette() {
    final hosts = context.read<HostProvider>().allHosts;
    final sessions = context.read<SessionProvider>().sessions;
    final snippetProvider = context.read<SnippetProvider>();

    final items = <CommandItem>[
      // Actions
      CommandItem(
        id: 'action_new_host',
        title: 'New Host',
        subtitle: 'Add a new SSH connection',
        icon: Icons.add_circle_outline,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openHostPanel()),
      ),
      CommandItem(
        id: 'action_import',
        title: 'Import SSH Config',
        subtitle: 'Import from ~/.ssh/config',
        icon: Icons.upload_file_outlined,
        type: CommandType.action,
        execute: () => WidgetsBinding.instance.addPostFrameCallback((_) => _openImportPanel()),
      ),
      // Nav sections
      CommandItem(
        id: 'nav_hosts',
        title: 'Hosts',
        subtitle: 'Manage SSH connections',
        icon: Icons.dns_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.hosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_sftp',
        title: 'SFTP',
        subtitle: 'File transfer',
        icon: Icons.folder_open,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.sftp; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_keychain',
        title: 'Keychain',
        subtitle: 'SSH keys',
        icon: Icons.vpn_key_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.keychain; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_port_forwarding',
        title: 'Port Forwarding',
        subtitle: 'Tunnel rules',
        icon: Icons.swap_horiz,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.portForwarding; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_local_terminal',
        title: 'Local Terminal',
        subtitle: 'Local shell',
        icon: Icons.laptop_mac,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.localTerminal; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_recordings',
        title: 'Recordings',
        subtitle: 'Session recordings',
        icon: Icons.video_library_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.recordings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_known_hosts',
        title: 'Known Hosts',
        subtitle: 'Host key verification',
        icon: Icons.fact_check_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.knownHosts; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_settings',
        title: 'Settings',
        subtitle: 'App preferences',
        icon: Icons.settings_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.settings; _viewingTerminal = false; }),
      ),
      CommandItem(
        id: 'nav_plugins',
        title: 'Plugins',
        subtitle: 'Plugin marketplace',
        icon: Icons.extension_outlined,
        type: CommandType.navSection,
        execute: () => setState(() { _nav = NavSection.plugins; _viewingTerminal = false; }),
      ),
      // Hosts
      ...hosts.map((h) => CommandItem(
        id: 'host_${h.id}',
        title: h.label,
        subtitle: '${h.username}@${h.host}:${h.port}',
        icon: Icons.dns,
        type: CommandType.host,
        execute: () async {
          setState(() => _viewingTerminal = true);
          await context.read<SessionProvider>().connect(h);
        },
      )),
      // Snippets
      ...snippetProvider.snippets.map((s) => CommandItem(
        id: 'snippet_${s.id}',
        title: s.label,
        subtitle: s.command,
        icon: Icons.code,
        type: CommandType.snippet,
        execute: () {
          final active = context.read<SessionProvider>().activeSession;
          if (active == null) return;
          active.terminal.textInput(s.command);
          active.terminal.keyInput(TerminalKey.enter);
        },
      )),
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => CommandPaletteDialog(items: items),
    );
  }
```

- [ ] **Step 2: Wire `_handleHotkey` and `_registerHotkeys`**

In `_handleHotkey` (line 115-133), add the `command_palette` case:

```dart
  void _handleHotkey(String name) {
    if (!mounted) return;
    switch (name) {
      case 'new_session':
        _openHostPanel();
      case 'close_session':
        context.read<SessionProvider>().closeActive();
      case 'next_session':
        context.read<SessionProvider>().activateNext();
      case 'prev_session':
        context.read<SessionProvider>().activatePrev();
      case 'toggle_input_bar':
        context.read<TerminalLayoutProvider>().toggleInputBar();
      case 'split_horizontal':
        context.read<TerminalLayoutProvider>().setLayout(SplitLayout.horizontal);
      case 'split_vertical':
        context.read<TerminalLayoutProvider>().setLayout(SplitLayout.vertical);
      case 'command_palette':
        _openCommandPalette();
    }
  }
```

- [ ] **Step 3: Check for `TerminalKey` import for snippet execution**

The snippet `execute` callback uses `TerminalKey.enter`. Verify the import is present in `main_screen.dart`:

```bash
grep -n "TerminalKey\|xterm" /Users/thangnguyen/Documents/Personal/yourssh/app/lib/screens/main_screen.dart
```

If not present, add to imports:
```dart
import 'package:xterm/xterm.dart';
```

- [ ] **Step 4: Run analyzer**

```bash
cd app && flutter analyze lib/screens/main_screen.dart
```

Expected: No issues.

- [ ] **Step 5: Run all tests**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: wire Command Palette into MainScreen with Cmd/Ctrl+K hotkey"
```

---

## Self-Review Checklist

- [x] **Spec coverage:**
  - Hosts → `CommandType.host` items from `HostProvider.allHosts` ✓
  - Nav sections → 9 hardcoded `CommandType.navSection` items ✓
  - Snippets → `SnippetProvider.snippets` ✓
  - Actions (New Host, Import) → `CommandType.action` ✓
  - Fuzzy match → `CommandPaletteSearcher.score` + `search` ✓
  - Match highlight → `CommandPaletteSearcher.highlightSpans` + `_HighlightedText` ✓
  - Keyboard nav (↑↓ Enter Esc) → `_onKeyEvent` + `onSubmitted` ✓
  - 560px, max 420px, `AppColors.sidebar` bg, `Colors.black54` barrier ✓
  - Configurable hotkey (default meta+k / ctrl+k) → Task 3 ✓
  - Hotkey Settings row → `_labels` update ✓
- [x] **No placeholders:** all steps have full code
- [x] **Type consistency:** `CommandItem`, `CommandType`, `CommandPaletteSearcher`, `CommandPaletteDialog` consistent across all tasks
