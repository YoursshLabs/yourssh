# Terminal Config Panel — Design

**Date:** 2026-06-04
**Status:** Approved

## Goal

Expose terminal appearance settings (font size, font family, color theme) directly in the terminal workspace as a collapsible right-side panel, mirroring the existing snippets panel — so users don't have to leave the session to tweak the terminal look.

## Decisions

- **Scope: global.** The panel edits `SettingsProvider` directly — the same values as the Settings screen, applied to all terminals (SSH + local). No per-session overrides.
- **Contents:** color theme picker, font size slider (10–24pt), font family dropdown (8 bundled fonts + Custom… free-text).
- **Mutual exclusivity:** only one right-side panel (snippets *or* terminal config) is open at a time. Opening one closes the other.

## Architecture

### 1. State — `TerminalLayoutProvider` (`app/lib/providers/terminal_layout_provider.dart`)

Replace `bool _snippetsPanelVisible` with an enum:

```dart
enum SidePanel { none, snippets, terminalConfig }

SidePanel _sidePanel = SidePanel.none;
SidePanel get sidePanel => _sidePanel;
bool get snippetsPanelVisible => _sidePanel == SidePanel.snippets;       // preserved API
bool get configPanelVisible => _sidePanel == SidePanel.terminalConfig;

void toggleSidePanel(SidePanel panel) {
  _sidePanel = (_sidePanel == panel) ? SidePanel.none : panel;
  notifyListeners();
}
```

`toggleSnippetsPanel()` is kept as an alias for `toggleSidePanel(SidePanel.snippets)` so existing callers (`broadcast_toolbar.dart`, `split_terminal_view.dart`) keep working. Mutual exclusivity is enforced by construction: toggling a different panel replaces the open one.

### 2. Shared controls — new `app/lib/widgets/terminal_appearance_controls.dart`

Extract the three controls from `settings_screen.dart` (Terminal section, ~lines 134–202) into a reusable `TerminalAppearanceControls` StatefulWidget with a `layout` parameter:

- `rows` — label left / control right (Settings screen style)
- `vertical` — label above control (for the narrow 340px panel)

Controls:

- **Color theme:** existing `ThemePickerButton`, unchanged.
- **Font size:** `Slider` 10–24, 14 divisions; calls `SettingsProvider.save(fontSize:)` on drag — terminals update live because `TerminalView` reads `settings.fontSize` via `watch`.
- **Font family:** dropdown of 8 bundled fonts + `Custom…` entry revealing a text field with an Apply button. The `_pendingCustom` / `_customFontController` state, the `_bundledFonts` list, the `_kCustom` sentinel, and the `didChangeDependencies` custom-font prefill all move from `settings_screen.dart` into this widget; the Settings screen no longer needs any of them.

The Settings screen's Terminal section becomes a single `TerminalAppearanceControls(layout: rows)` call. All writes go through `SettingsProvider.save()` as today — no new state, no new persistence.

### 3. Panel widget — new `app/lib/widgets/terminal_config_panel.dart`

Follows the `TerminalSnippetsPanel` skeleton:

- `Container` width 340, background `0xFF141414`, left border `0xFF2A2A2A`
- Header: title **"Terminal"** + close (X) button — no search field
- Body: `ListView` containing `TerminalAppearanceControls(layout: vertical)`

### 4. Wiring

- `broadcast_toolbar.dart`: add a `_LayoutButton` (icon `Icons.tune`, tooltip "Toggle Terminal Settings", `selected: layout.configPanelVisible`, `onTap: () => layout.toggleSidePanel(SidePanel.terminalConfig)`) next to the snippets icon.
- `split_terminal_view.dart`: in the workspace Row, after the snippets panel block, add `if (layout.configPanelVisible) TerminalConfigPanel(onClose: () => layout.toggleSidePanel(SidePanel.terminalConfig))`.

## Error handling

No new I/O. The only failure mode is a custom font name that doesn't exist on the system; current behavior (Flutter's font fallback) is preserved.

## Testing

- **`terminal_layout_provider` tests:** toggle open/close; mutual exclusivity (opening config while snippets is open closes snippets, and vice versa); `toggleSnippetsPanel()` alias still works.
- **`TerminalConfigPanel` widget tests:** renders all three controls; dragging the slider calls `SettingsProvider.save(fontSize:)`; selecting Custom… reveals the text field; X button fires `onClose`.
- **Settings screen:** existing tests still pass after the refactor.
