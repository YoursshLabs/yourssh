# Terminal Config Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible right-side "Terminal" settings panel (font size, font family, color theme) to the terminal workspace, mirroring the existing snippets panel, mutually exclusive with it.

**Architecture:** `TerminalLayoutProvider` gains a `SidePanel` enum replacing the snippets bool (mutual exclusivity by construction). The three appearance controls are extracted from `settings_screen.dart` into a shared `TerminalAppearanceControls` widget used by both the Settings screen (rows layout) and a new `TerminalConfigPanel` (vertical layout). All values read/write `SettingsProvider` — no new persistence.

**Tech Stack:** Flutter (desktop), provider (ChangeNotifier), shared_preferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-04-terminal-config-panel-design.md`

**Working directory:** all commands run from `app/` inside the repo.

---

### Task 1: `SidePanel` enum in TerminalLayoutProvider

**Files:**
- Modify: `app/lib/providers/terminal_layout_provider.dart`
- Test: `app/test/providers/terminal_layout_provider_test.dart`

- [ ] **Step 1: Add failing tests**

Append inside `main()` in `app/test/providers/terminal_layout_provider_test.dart` (after the existing `toggleSnippetsPanel notifies listeners` test):

```dart
  test('sidePanel defaults to none', () {
    final p = TerminalLayoutProvider();
    expect(p.sidePanel, SidePanel.none);
    expect(p.configPanelVisible, false);
  });

  test('toggleSidePanel opens and closes the same panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, true);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, false);
    expect(p.sidePanel, SidePanel.none);
  });

  test('opening config panel closes snippets panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, true);
    expect(p.snippetsPanelVisible, false);
  });

  test('opening snippets panel closes config panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSidePanel(SidePanel.terminalConfig);
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    expect(p.configPanelVisible, false);
  });

  test('toggleSidePanel notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(notificationCount, 1);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/terminal_layout_provider_test.dart`
Expected: COMPILE ERROR — `SidePanel` / `sidePanel` / `configPanelVisible` / `toggleSidePanel` undefined.

- [ ] **Step 3: Implement the enum in the provider**

Replace the full contents of `app/lib/providers/terminal_layout_provider.dart` with:

```dart
// app/lib/providers/terminal_layout_provider.dart
import 'package:flutter/foundation.dart';

enum SplitLayout { single, horizontal, vertical, quad }

/// Which right-side workspace panel is open. Only one at a time.
enum SidePanel { none, snippets, terminalConfig }

class TerminalLayoutProvider extends ChangeNotifier {
  SplitLayout _layout = SplitLayout.single;
  bool _broadcastEnabled = false;
  bool _inputBarVisible = false;
  SidePanel _sidePanel = SidePanel.none;

  SplitLayout get layout => _layout;
  bool get broadcastEnabled => _broadcastEnabled;
  bool get inputBarVisible => _inputBarVisible;
  SidePanel get sidePanel => _sidePanel;
  bool get snippetsPanelVisible => _sidePanel == SidePanel.snippets;
  bool get configPanelVisible => _sidePanel == SidePanel.terminalConfig;

  int get paneCount => switch (_layout) {
    SplitLayout.single => 1,
    SplitLayout.horizontal => 2,
    SplitLayout.vertical => 2,
    SplitLayout.quad => 4,
  };

  void setLayout(SplitLayout layout) {
    _layout = layout;
    notifyListeners();
  }

  void toggleBroadcast() {
    _broadcastEnabled = !_broadcastEnabled;
    notifyListeners();
  }

  void toggleInputBar() {
    _inputBarVisible = !_inputBarVisible;
    notifyListeners();
  }

  /// Toggles [panel]: opens it, or closes it if already open.
  /// Opening one panel replaces whichever other panel was open.
  void toggleSidePanel(SidePanel panel) {
    _sidePanel = (_sidePanel == panel) ? SidePanel.none : panel;
    notifyListeners();
  }

  void toggleSnippetsPanel() => toggleSidePanel(SidePanel.snippets);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/terminal_layout_provider_test.dart`
Expected: ALL PASS (old snippets tests + 5 new tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/terminal_layout_provider.dart app/test/providers/terminal_layout_provider_test.dart
git commit -m "feat(terminal): generalize side-panel state to SidePanel enum"
```

---

### Task 2: Shared `TerminalAppearanceControls` widget

**Files:**
- Create: `app/lib/widgets/terminal_appearance_controls.dart`
- Test: `app/test/widgets/terminal_appearance_controls_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `app/test/widgets/terminal_appearance_controls_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/widgets/terminal_appearance_controls.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(SettingsProvider settings,
      {AppearanceControlsLayout layout = AppearanceControlsLayout.vertical}) {
    return ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TerminalAppearanceControls(layout: layout),
          ),
        ),
      ),
    );
  }

  testWidgets('renders all three controls', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('rows layout renders the same controls', (tester) async {
    await tester.pumpWidget(
        wrap(SettingsProvider(), layout: AppearanceControlsLayout.rows));
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
  });

  testWidgets('dragging slider updates fontSize', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(wrap(settings));
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    expect(settings.fontSize, greaterThan(13));
  });

  testWidgets('selecting Custom… shows the custom font field', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    expect(find.text('Custom font name'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Apply saves the custom font name', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(wrap(settings));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hack Nerd Font');
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(settings.terminalFont, 'Hack Nerd Font');
  });

  testWidgets('non-bundled font prefills the custom field', (tester) async {
    final settings = SettingsProvider()..terminalFont = 'My Font';
    await tester.pumpWidget(wrap(settings));
    expect(find.text('Custom font name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'My Font'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/terminal_appearance_controls_test.dart`
Expected: COMPILE ERROR — `terminal_appearance_controls.dart` does not exist.

- [ ] **Step 3: Create the widget**

Create `app/lib/widgets/terminal_appearance_controls.dart`:

```dart
// app/lib/widgets/terminal_appearance_controls.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'theme_picker.dart';

/// How [TerminalAppearanceControls] lays out each control.
enum AppearanceControlsLayout {
  /// Label left, control right — Settings screen style.
  rows,

  /// Label above control — for the narrow side panel.
  vertical,
}

/// Fonts bundled with the app, selectable without typing a name.
const kBundledTerminalFonts = [
  'monospace',
  'MesloLGS NF',
  'DejaVu Sans Mono for Powerline',
  'Inconsolata for Powerline',
  'Meslo LG S for Powerline',
  'Source Code Pro for Powerline',
  'Ubuntu Mono derivative Powerline',
  'Roboto Mono for Powerline',
];

const _kCustom = '__custom__';

/// Terminal appearance settings (color theme, font size, font family),
/// shared between the Settings screen and the terminal config side panel.
/// Reads and writes [SettingsProvider] directly.
class TerminalAppearanceControls extends StatefulWidget {
  final AppearanceControlsLayout layout;

  const TerminalAppearanceControls({super.key, required this.layout});

  @override
  State<TerminalAppearanceControls> createState() =>
      _TerminalAppearanceControlsState();
}

class _TerminalAppearanceControlsState
    extends State<TerminalAppearanceControls> {
  final _customFontController = TextEditingController();
  bool _pendingCustom = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final font = context.read<SettingsProvider>().terminalFont;
    final isCustom = !kBundledTerminalFonts.contains(font);
    if (isCustom && _customFontController.text.isEmpty) {
      _customFontController.text = font;
    }
  }

  @override
  void dispose() {
    _customFontController.dispose();
    super.dispose();
  }

  bool get _isRows => widget.layout == AppearanceControlsLayout.rows;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final showCustom =
        _pendingCustom || !kBundledTerminalFonts.contains(settings.terminalFont);

    final entries = <(String, Widget)>[
      (
        'Color theme',
        ThemePickerButton(
          currentTheme: settings.terminalTheme,
          onChanged: (v) =>
              context.read<SettingsProvider>().save(terminalTheme: v),
        ),
      ),
      (
        'Font size: ${settings.fontSize.round()}pt',
        SizedBox(
          width: _isRows ? 200 : double.infinity,
          child: Slider(
            value: settings.fontSize,
            min: 10,
            max: 24,
            divisions: 14,
            onChanged: (v) =>
                context.read<SettingsProvider>().save(fontSize: v),
          ),
        ),
      ),
      ('Terminal font', _buildFontDropdown(context, settings)),
      if (showCustom) ('Custom font name', _buildCustomFontField(context)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, entry) in entries.indexed) ..._buildEntry(i, entry),
      ],
    );
  }

  List<Widget> _buildEntry(int index, (String, Widget) entry) {
    final (label, control) = entry;
    if (_isRows) {
      return [
        if (index > 0)
          const Divider(height: 1, color: AppColors.border, indent: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
              ),
              control,
            ],
          ),
        ),
      ];
    }
    return [
      if (index > 0) const SizedBox(height: 16),
      Text(label,
          style:
              const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      const SizedBox(height: 6),
      control,
    ];
  }

  Widget _buildFontDropdown(BuildContext context, SettingsProvider settings) {
    final isCustom = !kBundledTerminalFonts.contains(settings.terminalFont);
    final ddValue = (isCustom || _pendingCustom) ? _kCustom : settings.terminalFont;
    return DropdownButton<String>(
      value: ddValue,
      isExpanded: !_isRows,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: [
        ...kBundledTerminalFonts.map((f) => DropdownMenuItem(
              value: f,
              child: Text(f == 'monospace' ? 'System Default' : f,
                  style: const TextStyle(fontSize: 12)),
            )),
        const DropdownMenuItem(
          value: _kCustom,
          child: Text('Custom…', style: TextStyle(fontSize: 12)),
        ),
      ],
      onChanged: (v) {
        if (v == _kCustom) {
          setState(() {
            _pendingCustom = true;
            _customFontController.clear();
          });
        } else if (v != null) {
          setState(() => _pendingCustom = false);
          context.read<SettingsProvider>().save(terminalFont: v);
        }
      },
    );
  }

  Widget _buildCustomFontField(BuildContext context) {
    return SizedBox(
      width: _isRows ? 220 : double.infinity,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _customFontController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'e.g. Hack Nerd Font',
                hintStyle:
                    const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () {
              final name = _customFontController.text.trim();
              if (name.isEmpty) return;
              setState(() => _pendingCustom = false);
              context.read<SettingsProvider>().save(terminalFont: name);
            },
            child: const Text('Apply', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/terminal_appearance_controls_test.dart`
Expected: ALL PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/terminal_appearance_controls.dart app/test/widgets/terminal_appearance_controls_test.dart
git commit -m "feat(terminal): extract shared TerminalAppearanceControls widget"
```

---

### Task 3: Settings screen uses the shared widget

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart` (Terminal section ~lines 134–202; state members ~lines 31–60; `_buildFontDropdown` ~lines 378–409)

- [ ] **Step 1: Replace the Terminal section**

In `app/lib/widgets/settings_screen.dart`, replace the whole `_Section(title: 'Terminal', children: [...])` block (from `_Section(title: 'Terminal', children: [` through its closing `]),` — currently lines 134–202) with:

```dart
                _Section(title: 'Terminal', children: const [
                  TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ]),
```

Add the import at the top of the file (with the other relative imports):

```dart
import 'terminal_appearance_controls.dart';
```

- [ ] **Step 2: Remove the now-dead font state from `_SettingsScreenState`**

Delete from `_SettingsScreenState`:
- the `_bundledFonts` static const list (lines 31–40)
- the `_kCustom` const (line 41)
- the `_customFontController` field and `_pendingCustom` field (lines 43–44)
- the `didChangeDependencies()` override (lines 46–54)
- the `dispose()` override (lines 56–60 — it only disposes `_customFontController`)
- the entire `_buildFontDropdown(...)` method (lines ~378–409)

- [ ] **Step 3: Analyze and fix unused imports**

Run: `cd app && flutter analyze`
Expected: no errors. If `theme_picker.dart` or `flutter/services.dart` is now reported unused in `settings_screen.dart`, remove that import (check first — `theme_picker.dart` may still be used elsewhere in the file, e.g. exported types).

- [ ] **Step 4: Run the full test suite**

Run: `cd app && flutter test`
Expected: ALL PASS — existing settings-screen behavior is preserved via the shared widget.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "refactor(settings): use shared TerminalAppearanceControls in Terminal section"
```

---

### Task 4: `TerminalConfigPanel` widget

**Files:**
- Create: `app/lib/widgets/terminal_config_panel.dart`
- Test: `app/test/widgets/terminal_config_panel_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `app/test/widgets/terminal_config_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/widgets/terminal_config_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap({VoidCallback? onClose}) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Row(children: [TerminalConfigPanel(onClose: onClose)]),
        ),
      ),
    );
  }

  testWidgets('renders title and appearance controls', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
  });

  testWidgets('close button fires onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(wrap(onClose: () => closed = true));
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, true);
  });

  testWidgets('panel is 340 wide', (tester) async {
    await tester.pumpWidget(wrap());
    final size = tester.getSize(find.byType(TerminalConfigPanel));
    expect(size.width, 340);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/terminal_config_panel_test.dart`
Expected: COMPILE ERROR — `terminal_config_panel.dart` does not exist.

- [ ] **Step 3: Create the panel widget**

Create `app/lib/widgets/terminal_config_panel.dart`:

```dart
// app/lib/widgets/terminal_config_panel.dart
import 'package:flutter/material.dart';
import 'terminal_appearance_controls.dart';

/// Right-side workspace panel for terminal appearance settings.
/// Mirrors [TerminalSnippetsPanel]'s frame (340px, dark, left border).
class TerminalConfigPanel extends StatelessWidget {
  final VoidCallback? onClose;

  const TerminalConfigPanel({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(left: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
            ),
            child: Row(
              children: [
                const Text(
                  'Terminal',
                  style: TextStyle(
                    color: Color(0xFFE5E5E5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close terminal settings',
                    onPressed: onClose,
                    icon: const Icon(Icons.close,
                        size: 16, color: Color(0xFF888888)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                TerminalAppearanceControls(
                  layout: AppearanceControlsLayout.vertical,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/terminal_config_panel_test.dart`
Expected: ALL PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/terminal_config_panel.dart app/test/widgets/terminal_config_panel_test.dart
git commit -m "feat(terminal): add TerminalConfigPanel side panel"
```

---

### Task 5: Wire toolbar button and workspace layout

**Files:**
- Modify: `app/lib/widgets/broadcast_toolbar.dart` (after the snippets `_LayoutButton`, ~line 51)
- Modify: `app/lib/widgets/split_terminal_view.dart` (workspace Row, ~lines 52–62)
- Test: `app/test/widgets/broadcast_toolbar_test.dart`

- [ ] **Step 1: Write failing toolbar test**

Create `app/test/widgets/broadcast_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/widgets/broadcast_toolbar.dart';

void main() {
  Widget wrap(TerminalLayoutProvider layout) {
    return ChangeNotifierProvider.value(
      value: layout,
      child: const MaterialApp(home: Scaffold(body: BroadcastToolbar())),
    );
  }

  testWidgets('tune button toggles the terminal config panel', (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout));

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, true);

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, false);
  });

  testWidgets('opening config panel from toolbar closes snippets panel',
      (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout));

    await tester.tap(find.byTooltip('Toggle Snippets Panel'));
    await tester.pump();
    expect(layout.snippetsPanelVisible, true);

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, true);
    expect(layout.snippetsPanelVisible, false);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/broadcast_toolbar_test.dart`
Expected: FAIL — no widget with tooltip 'Toggle Terminal Settings'.

- [ ] **Step 3: Add the toolbar button**

In `app/lib/widgets/broadcast_toolbar.dart`, directly after the snippets `_LayoutButton` (the one with `icon: Icons.code`, ends ~line 51), add:

```dart
          _LayoutButton(
            icon: Icons.tune,
            tooltip: 'Toggle Terminal Settings',
            selected: layout.configPanelVisible,
            onTap: () => layout.toggleSidePanel(SidePanel.terminalConfig),
          ),
```

- [ ] **Step 4: Mount the panel in the workspace**

In `app/lib/widgets/split_terminal_view.dart`:

Add the import (next to the `terminal_snippets_panel.dart` import, ~line 15):

```dart
import 'terminal_config_panel.dart';
```

In the workspace `Row` (inside `Expanded`, ~lines 52–62), after the `if (layout.snippetsPanelVisible) TerminalSnippetsPanel(...)` block, add:

```dart
              if (layout.configPanelVisible)
                TerminalConfigPanel(
                  onClose: () => layout.toggleSidePanel(SidePanel.terminalConfig),
                ),
```

- [ ] **Step 5: Run toolbar test to verify it passes**

Run: `cd app && flutter test test/widgets/broadcast_toolbar_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Analyze and run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: analyze clean, ALL tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/broadcast_toolbar.dart app/lib/widgets/split_terminal_view.dart app/test/widgets/broadcast_toolbar_test.dart
git commit -m "feat(terminal): wire terminal config panel into toolbar and workspace"
```

---

### Task 6: Manual smoke check (optional but recommended)

- [ ] **Step 1: Run the app**

Run: `cd app && flutter run -d macos`

Verify:
1. Open an SSH or local terminal session.
2. Click the tune icon in the toolbar → 340px "Terminal" panel opens on the right.
3. Drag the font size slider → terminal text resizes live.
4. Change the font / theme → applies live.
5. Click the snippets (code) icon → config panel closes, snippets panel opens.
6. Settings screen → Terminal section still renders and works identically.
