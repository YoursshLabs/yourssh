# Keyword Highlighting — Design Spec

**Date:** 2026-06-07  
**Status:** Approved  
**Scope:** Global keyword highlight rules that tint matching text in all terminal sessions (SSH + local shell)

---

## Overview

User-defined regex/literal rules that highlight matching text in terminal output with a configurable foreground color, background color, or both. Ships with verbose defaults (error/warning/success/done/ok/debug/info). Managed in Settings → Terminal and togglable per-rule in the workspace side panel.

Implementation is a **render-layer overlay** inside the xterm fork — data is never modified, recordings are unaffected.

---

## Data Model

### App layer — `app/lib/models/keyword_highlight_rule.dart`

```dart
class AppKeywordHighlightRule {
  final String id;           // UUID — stable key for reorder/delete
  final String label;        // display name ("Error", "Warning" …)
  final String pattern;      // raw string entered by user
  final bool isRegex;        // false → pattern is treated as literal (auto-escaped)
  final bool caseSensitive;  // default false
  final bool enabled;
  final Color? foreground;   // null = don't override text color
  final Color? background;   // null = don't tint background
}
```

- Stored as JSON array in `SharedPreferences['keywordHighlightRules']`.
- Color stored as int (`Color.value`).
- `toXtermRule()` compiles the regex and returns an `xterm.KeywordHighlightRule`; if the pattern is invalid it returns null and the rule is silently skipped.
- `toJson()` / `fromJson()` for persistence.
- Maximum 20 rules enforced in the settings UI (performance cap).

### xterm layer — `packages/xterm/lib/src/ui/keyword_highlight.dart`

```dart
class KeywordHighlightRule {
  final RegExp pattern;      // pre-compiled, ready for allMatches()
  final Color? foreground;
  final Color? background;
}
```

The xterm package has no knowledge of labels, ids, or enabled state — those are filtered at the app layer before passing compiled rules into `TerminalView`.

### Default rules

All rules are case-insensitive (`caseSensitive: false`).

| Label   | Pattern       | isRegex | Foreground           | Background             |
|---------|---------------|---------|----------------------|------------------------|
| Error   | `error`       | false   | —                    | `Colors.red.shade700`  |
| Fail    | `fail`        | false   | —                    | `Colors.red.shade700`  |
| Warning | `warning`     | false   | —                    | `Colors.orange.shade700` |
| Warn    | `warn`        | false   | —                    | `Colors.orange.shade700` |
| Success | `success`     | false   | `Colors.green.shade300` | —                   |
| Done    | `done`        | false   | `Colors.green.shade300` | —                   |
| OK      | `\bok\b`      | true    | `Colors.green.shade300` | —                   |
| Debug   | `debug`       | false   | `Colors.grey.shade500`  | —                   |
| Info    | `info`        | false   | `Colors.cyan.shade300`  | —                   |

`\bok\b` uses word boundaries to avoid matching "working", "broken", etc.

---

## Architecture & Data Flow

```
SettingsProvider
  .keywordHighlightingEnabled  (bool, default true)
  .keywordHighlightRules       (List<AppKeywordHighlightRule>, default kDefaultKeywordHighlightRules)
        │
        │  context.select — rebuild only when rules change
        ▼
_TerminalWidgetState.build()        [app/lib/widgets/terminal_view.dart]
  filters enabled rules
  calls .toXtermRule() on each
  → List<xterm.KeywordHighlightRule>
        │
        ▼
TerminalView(keywordRules: compiledRules)   [packages/xterm/lib/src/terminal_view.dart]
        │
        ▼
RenderTerminal._keywordRules
  paint() → _paintKeywordHighlights()
    iterates effectFirstLine..effectLastLine (visible viewport only)
    per line: getText() → regex.allMatches() → bg rect + fg re-render
```

**Paint order inside `_paint()`:**

1. `paintLine()` × visible lines — ANSI-colored text
2. `_paintKeywordHighlights()` — background rects, then foreground re-renders *(new)*
3. Cursor
4. `_paintHighlights()` — search overlays (visually on top of keyword highlights)
5. `_paintSelection()`

Search highlights win over keyword highlights by paint order — intended, since search is a user-initiated action.

**Local shell sessions:** Automatically supported. Feature lives in the xterm render layer, independent of `SshService` and `HookBus`. `LocalShellService` writes directly to `Terminal.write()` — same xterm object, same render path.

**Recordings:** Unaffected. `_recording?.writeOutput()` receives the original text before any render transform. ✅

---

## xterm Fork Changes

### 1. `packages/xterm/lib/src/ui/keyword_highlight.dart` *(new)*

Defines `KeywordHighlightRule` with pre-compiled `RegExp`, nullable `foreground`, nullable `background`. Exported from `xterm.dart`.

### 2. `packages/xterm/lib/src/ui/painter.dart`

Add `paintKeywordForeground(canvas, offset, line, startCol, endCol, Color)`:

- Iterates `startCol..endCol` cells on the given `BufferLine`.
- Re-renders each character with the override foreground color, bypassing `_paragraphCache` (cache keys include original ANSI color — can't reuse).
- Handles wide characters (charWidth == 2): skips the phantom second cell to match `paintLine()` behavior.
- Guards `endCol` against `line.length` to prevent out-of-bounds.

### 3. `packages/xterm/lib/src/ui/render.dart`

Add to `RenderTerminal`:

```dart
List<KeywordHighlightRule> _keywordRules = const [];
set keywordRules(List<KeywordHighlightRule> value) {
  _keywordRules = value;
  markNeedsPaint();
}
```

Add `_paintKeywordHighlights(canvas, offset, firstLine, lastLine)`:

```
for each visible line i:
  lineText = lines[i].getText()
  for each rule:
    for each match in rule.pattern.allMatches(lineText):
      if rule.background != null → _paintSegment(segment, rule.background)
      if rule.foreground != null → painter.paintKeywordForeground(…, m.start, m.end, rule.foreground)
```

Called in `_paint()` after the line-painting loop, before the cursor.

### 4. `packages/xterm/lib/src/terminal_view.dart`

Thread `List<KeywordHighlightRule> keywordRules = const []` from `TerminalView` → `_TerminalView` → `RenderTerminal.updateRenderObject()`.

---

## App-side Changes

### `app/lib/providers/settings_provider.dart`

Add:
- `bool keywordHighlightingEnabled = true`
- `List<AppKeywordHighlightRule> keywordHighlightRules = kDefaultKeywordHighlightRules`

Load from `SharedPreferences` in `load()`; persist in `save()` / `update()`. If key absent → use defaults (first-run experience shows verbose defaults immediately).

### `app/lib/widgets/terminal_view.dart`

In `_TerminalWidgetState.build()`:

```dart
final rules = context.select<SettingsProvider, List<xterm.KeywordHighlightRule>>(
  (s) => s.keywordHighlightingEnabled
      ? s.keywordHighlightRules
            .where((r) => r.enabled)
            .map((r) => r.toXtermRule())
            .whereType<xterm.KeywordHighlightRule>()
            .toList()
      : const [],
);
```

Pass `keywordRules: rules` into `TerminalView`.

### `app/lib/widgets/settings_screen.dart`

New "KEYWORD HIGHLIGHTING" section in the Terminal tab, after `TerminalAppearanceControls`:

- Master `SwitchListTile`: Enable keyword highlighting
- Rule list: each row shows color swatch(es) + label/pattern + per-rule enabled toggle + delete icon
- "Add rule" button (disabled when rule count ≥ 20)
- Add/Edit dialog fields: label, pattern, regex toggle, case-sensitive toggle, foreground color picker (nullable), background color picker (nullable)
- Color picker: simple grid of ~16 DevOps-friendly presets (no full HSV for V1) + a "None" option

### `app/lib/widgets/terminal_config_panel.dart`

Compact "KEYWORD HIGHLIGHTING" subsection after `TerminalAppearanceControls`:

- Master enable toggle
- Per-rule rows: label + color swatch(es) + enabled toggle (no add/edit/delete here)
- "Open Settings →" link that navigates to Settings → Terminal

---

## Edge Cases & Error Handling

| Case | Handling |
|------|----------|
| Invalid regex pattern | `toXtermRule()` returns null; rule silently skipped. Settings dialog validates real-time and shows "Invalid regex" inline. |
| Performance (busy log stream) | Only visible lines scanned per paint (~40–60 lines × ≤20 rules). Acceptable overhead. |
| ANSI codes in getText() | `BufferLine.getText()` returns plain text — ANSI already stripped. Column offsets from regex match map directly to cell columns. |
| Wide characters (CJK/emoji) | `paintKeywordForeground()` mirrors `paintLine()`'s `charWidth == 2` skip logic. |
| Scrollback pruning | No `CellAnchor` objects used. Highlights are computed fresh from the live buffer on every paint frame; pruned lines disappear naturally. |
| Alt-screen (vim, htop) | `_terminal.buffer.lines` points to the active buffer. Keyword rules apply to alt-screen content — minor visual noise acceptable for V1. |
| Rule count limit | Max 20 rules enforced in settings UI. `_paintKeywordHighlights()` requires no guard — the cap is at the input boundary. |

---

## Testing

- **Unit — `AppKeywordHighlightRule`**: `toXtermRule()` compiles regex correctly; invalid pattern returns null; `toJson()`/`fromJson()` roundtrip; `kDefaultKeywordHighlightRules` all compile without error.
- **Unit — `paintKeywordForeground()`**: Does not throw for empty line, `endCol > line.length`, wide-char cells.
- **Widget — `_TerminalWidgetState`**: When `keywordHighlightingEnabled = false`, an empty `keywordRules` list is passed to `TerminalView`. When a rule is disabled, it is excluded from the compiled list.

---

## Files Changed

| File | Change |
|------|--------|
| `packages/xterm/lib/src/ui/keyword_highlight.dart` | New |
| `packages/xterm/lib/src/ui/painter.dart` | +`paintKeywordForeground()` |
| `packages/xterm/lib/src/ui/render.dart` | +`keywordRules` property, +`_paintKeywordHighlights()` |
| `packages/xterm/lib/src/terminal_view.dart` | Thread `keywordRules` param |
| `packages/xterm/xterm.dart` | Export `KeywordHighlightRule` |
| `app/lib/models/keyword_highlight_rule.dart` | New — app model + defaults |
| `app/lib/providers/settings_provider.dart` | +2 fields + persist |
| `app/lib/widgets/terminal_view.dart` | Wire compiled rules into `TerminalView` |
| `app/lib/widgets/settings_screen.dart` | New keyword highlighting section |
| `app/lib/widgets/terminal_config_panel.dart` | Compact toggle section |
