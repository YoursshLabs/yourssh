# Terminal Snippets Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-side snippets panel inside the SSH terminal screen so users can browse, search, copy, and run snippets against the currently active pane without leaving terminal view.

**Architecture:** Extend `TerminalLayoutProvider` with snippets-panel visibility state, add a focused `TerminalSnippetsPanel` widget that reads `SnippetProvider`, and integrate that panel into `SplitTerminalView` beside the existing pane layout. Reuse the current active session from `SessionProvider` and reuse terminal input semantics by sending `command + "\n"` to the active connected SSH session.

**Tech Stack:** Flutter, Provider, existing `SnippetProvider`, existing terminal/session models, Flutter widget tests

---

## File Map

| File | Responsibility |
|---|---|
| `app/lib/providers/terminal_layout_provider.dart` | source of truth for snippets panel visibility |
| `app/lib/widgets/broadcast_toolbar.dart` | expose toolbar toggle for snippets panel |
| `app/lib/widgets/terminal_snippets_panel.dart` | terminal-side snippets search/list/run/copy UI |
| `app/lib/widgets/split_terminal_view.dart` | compose pane layout with optional right-side panel |
| `app/test/providers/terminal_layout_provider_test.dart` | provider state regression coverage |
| `app/test/widgets/terminal_snippets_panel_test.dart` | widget tests for search, copy, run, disabled state |

---

### Task 1: Add snippets-panel visibility state

**Files:**
- Modify: `app/lib/providers/terminal_layout_provider.dart`
- Modify: `app/test/providers/terminal_layout_provider_test.dart`

- [ ] **Step 1: Write the failing provider tests**

Add these tests to `app/test/providers/terminal_layout_provider_test.dart`:

```dart
test('snippetsPanelVisible defaults to false', () {
  final p = TerminalLayoutProvider();
  expect(p.snippetsPanelVisible, false);
});

test('toggleSnippetsPanel flips visibility', () {
  final p = TerminalLayoutProvider();
  p.toggleSnippetsPanel();
  expect(p.snippetsPanelVisible, true);
  p.toggleSnippetsPanel();
  expect(p.snippetsPanelVisible, false);
});

test('toggleSnippetsPanel notifies listeners', () {
  final p = TerminalLayoutProvider();
  var notificationCount = 0;
  p.addListener(() => notificationCount++);
  p.toggleSnippetsPanel();
  expect(notificationCount, 1);
});
```

- [ ] **Step 2: Run the provider tests to verify they fail**

Run:

```bash
flutter test test/providers/terminal_layout_provider_test.dart
```

Expected: FAIL with missing `snippetsPanelVisible` / `toggleSnippetsPanel`.

- [ ] **Step 3: Add the minimal provider state**

Update `app/lib/providers/terminal_layout_provider.dart` with:

```dart
class TerminalLayoutProvider extends ChangeNotifier {
  SplitLayout _layout = SplitLayout.single;
  bool _broadcastEnabled = false;
  bool _inputBarVisible = false;
  bool _snippetsPanelVisible = false;

  SplitLayout get layout => _layout;
  bool get broadcastEnabled => _broadcastEnabled;
  bool get inputBarVisible => _inputBarVisible;
  bool get snippetsPanelVisible => _snippetsPanelVisible;

  void toggleSnippetsPanel() {
    _snippetsPanelVisible = !_snippetsPanelVisible;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run the provider tests to verify they pass**

Run:

```bash
flutter test test/providers/terminal_layout_provider_test.dart
```

Expected: PASS.

---

### Task 2: Build the terminal snippets panel widget

**Files:**
- Create: `app/lib/widgets/terminal_snippets_panel.dart`
- Create: `app/test/widgets/terminal_snippets_panel_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `app/test/widgets/terminal_snippets_panel_test.dart` with these cases:

```dart
testWidgets('renders snippets from provider', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final provider = SnippetProvider();

  await tester.pumpWidget(
    ChangeNotifierProvider<SnippetProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: TerminalSnippetsPanel(
            canRun: true,
            onRunSnippet: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Disk usage'), findsOneWidget);
  expect(find.text('Memory info'), findsOneWidget);
});

testWidgets('search filters snippet rows', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final provider = SnippetProvider();

  await tester.pumpWidget(
    ChangeNotifierProvider<SnippetProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: TerminalSnippetsPanel(
            canRun: true,
            onRunSnippet: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), 'memory');
  await tester.pump();

  expect(find.text('Memory info'), findsOneWidget);
  expect(find.text('Disk usage'), findsNothing);
});

testWidgets('run action forwards selected snippet', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final provider = SnippetProvider();
  String? command;

  await tester.pumpWidget(
    ChangeNotifierProvider<SnippetProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: TerminalSnippetsPanel(
            canRun: true,
            onRunSnippet: (snippet) => command = snippet.command,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Run snippet').first);
  await tester.pump();

  expect(command, 'df -h');
});

testWidgets('run action is disabled when canRun is false', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final provider = SnippetProvider();
  String? command;

  await tester.pumpWidget(
    ChangeNotifierProvider<SnippetProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: TerminalSnippetsPanel(
            canRun: false,
            onRunSnippet: (snippet) => command = snippet.command,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('Run snippet').first);
  await tester.pump();

  expect(command, isNull);
  expect(find.text('No active SSH pane selected'), findsOneWidget);
});
```

- [ ] **Step 2: Run the widget tests to verify they fail**

Run:

```bash
flutter test test/widgets/terminal_snippets_panel_test.dart
```

Expected: FAIL because `TerminalSnippetsPanel` does not exist.

- [ ] **Step 3: Create the minimal panel widget**

Create `app/lib/widgets/terminal_snippets_panel.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

class TerminalSnippetsPanel extends StatefulWidget {
  final bool canRun;
  final ValueChanged<Snippet> onRunSnippet;
  final VoidCallback? onClose;

  const TerminalSnippetsPanel({
    super.key,
    required this.canRun,
    required this.onRunSnippet,
    this.onClose,
  });

  @override
  State<TerminalSnippetsPanel> createState() => _TerminalSnippetsPanelState();
}
```

and implement:

- fixed width right panel (`320` to `360` px)
- search field
- filtered list from `context.watch<SnippetProvider>().snippets`
- row actions:
  - `Run snippet` button calls `onRunSnippet(snippet)` only when `canRun`
  - `Copy snippet` writes `snippet.command` to clipboard
- disabled banner text `No active SSH pane selected` when `canRun == false`

- [ ] **Step 4: Run the widget tests to verify they pass**

Run:

```bash
flutter test test/widgets/terminal_snippets_panel_test.dart
```

Expected: PASS.

---

### Task 3: Add toolbar toggle and integrate panel into split terminal view

**Files:**
- Modify: `app/lib/widgets/broadcast_toolbar.dart`
- Modify: `app/lib/widgets/split_terminal_view.dart`

- [ ] **Step 1: Add a failing toolbar/panel integration test**

Add this case to `app/test/widgets/terminal_snippets_panel_test.dart`:

```dart
testWidgets('toolbar toggle controls snippets panel visibility', (tester) async {
  final layout = TerminalLayoutProvider();

  await tester.pumpWidget(
    ChangeNotifierProvider<TerminalLayoutProvider>.value(
      value: layout,
      child: const MaterialApp(
        home: Scaffold(
          body: BroadcastToolbar(),
        ),
      ),
    ),
  );

  expect(layout.snippetsPanelVisible, false);

  await tester.tap(find.byTooltip('Toggle Snippets Panel'));
  await tester.pump();

  expect(layout.snippetsPanelVisible, true);
});
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
flutter test test/widgets/terminal_snippets_panel_test.dart --plain-name "toolbar toggle controls snippets panel visibility"
```

Expected: FAIL because the toolbar toggle does not exist.

- [ ] **Step 3: Add the toolbar toggle**

In `app/lib/widgets/broadcast_toolbar.dart`, add a snippets toggle before the
`Spacer()`:

```dart
_LayoutButton(
  icon: Icons.code,
  tooltip: 'Toggle Snippets Panel',
  selected: layout.snippetsPanelVisible,
  onTap: layout.toggleSnippetsPanel,
),
const SizedBox(width: 8),
```

- [ ] **Step 4: Integrate the panel into split terminal view**

Update `app/lib/widgets/split_terminal_view.dart` so `build()` returns:

```dart
return Column(
  children: [
    const BroadcastToolbar(),
    Expanded(
      child: Row(
        children: [
          Expanded(child: _buildPanes(context, layout, sessions)),
          if (layout.snippetsPanelVisible)
            TerminalSnippetsPanel(
              canRun: _canRunSnippetTarget(context),
              onRunSnippet: (snippet) => _runSnippetOnActive(context, snippet.command),
            ),
        ],
      ),
    ),
  ],
);
```

Implement helpers in `SplitTerminalView`:

```dart
bool _canRunSnippetTarget(BuildContext context) {
  final active = context.read<SessionProvider>().activeSession;
  return active != null &&
      !active.isWatch &&
      active.status == SessionStatus.connected;
}

void _runSnippetOnActive(BuildContext context, String command) {
  final active = context.read<SessionProvider>().activeSession;
  if (active == null || active.isWatch || active.status != SessionStatus.connected) {
    return;
  }
  active.terminal.textInput('$command\n');
}
```

- [ ] **Step 5: Run the combined terminal snippets tests**

Run:

```bash
flutter test \
  test/providers/terminal_layout_provider_test.dart \
  test/widgets/terminal_snippets_panel_test.dart
```

Expected: PASS.

---

### Task 4: Verify touched app files still analyze cleanly

**Files:**
- Verify: `app/lib/providers/terminal_layout_provider.dart`
- Verify: `app/lib/widgets/broadcast_toolbar.dart`
- Verify: `app/lib/widgets/terminal_snippets_panel.dart`
- Verify: `app/lib/widgets/split_terminal_view.dart`

- [ ] **Step 1: Run focused analyzer verification**

Run:

```bash
flutter analyze \
  lib/providers/terminal_layout_provider.dart \
  lib/widgets/broadcast_toolbar.dart \
  lib/widgets/terminal_snippets_panel.dart \
  lib/widgets/split_terminal_view.dart
```

Expected: `No issues found!`

- [ ] **Step 2: Re-run the full targeted test set used by this change**

Run:

```bash
flutter test \
  test/providers/terminal_layout_provider_test.dart \
  test/widgets/terminal_snippets_panel_test.dart \
  test/widgets/terminal_input_bar_test.dart
```

Expected: PASS with zero failures.
