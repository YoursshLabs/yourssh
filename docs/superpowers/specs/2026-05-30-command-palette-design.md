# Command Palette — Design Spec

**Date:** 2026-05-30
**Status:** Approved, ready for implementation

---

## Overview

Global fuzzy-search overlay triggered by `Cmd+K` (macOS) / `Ctrl+K` (Win/Linux). Lets users connect to hosts, navigate sections, run snippets, and trigger actions without touching the mouse.

---

## Data Model

```dart
enum CommandType { host, navSection, snippet, action }

class CommandItem {
  final String id;
  final String title;
  final String subtitle; // e.g. "user@host:22", "Navigation", "Snippet"
  final IconData icon;
  final CommandType type;
  final VoidCallback execute;
  final int score; // populated during search, 0 at rest
}
```

---

## Item Sources

| Type | Source | Execute action |
|---|---|---|
| `host` | `HostProvider.allHosts` | `SessionProvider.connect(host)` + `_viewingTerminal = true` |
| `navSection` | Hardcoded 9 `NavSection` entries | `setState(_nav = section)` |
| `snippet` | `SnippetProvider` (when plugin enabled) | Exec snippet on active SSH session |
| `action` | Hardcoded: New Host, Import SSH Config | `_openHostPanel()`, `_openImportPanel()` |

---

## Search Algorithm

Character-subsequence fuzzy scoring (no external package required):

- For each candidate title, compute how many characters of the query appear as a subsequence, weighted by contiguous runs and prefix matches.
- Example: query `"pd"` scores higher against `"prod-db"` than `"padding"`.
- Query empty → show all items grouped: Actions → Nav Sections → Hosts → Snippets.
- Query non-empty → sort descending by score, hide zero-score items, no grouping.
- Logic lives in `CommandPaletteSearcher` (static pure functions, unit-testable in isolation).

---

## UI

### Layout

```
┌──────────────────────────────────────────┐
│  🔍 [search input.......................]  │  ← autofocus, Escape closes
├──────────────────────────────────────────┤
│  [icon]  title           subtitle  type  │  ← selected row (highlighted)
│  [icon]  title           subtitle        │
│  [icon]  title           subtitle        │
│  ...                                     │
├──────────────────────────────────────────┤
│  ↑↓ navigate   ↵ execute   esc close    │  ← hint bar
└──────────────────────────────────────────┘
```

- **Width:** 560 px fixed, centered horizontally and vertically
- **Max height:** 420 px; result list scrolls if needed
- **Max visible items:** 8
- **Background:** `AppColors.sidebar` with `barrierColor: Colors.black54`
- **Match highlight:** matched characters rendered bold via `RichText` + `TextSpan`

### Keyboard

| Key | Action |
|---|---|
| `↑` / `↓` | Move selection |
| `Enter` | Execute selected item |
| `Escape` | Close palette |
| Any character | Filter results in real-time |

---

## Hotkey

- Default: `meta+k` on macOS, `ctrl+k` on Win/Linux.
- Stored in `SettingsProvider.hotkeys` under key `command_palette`.
- Configurable via `HotkeySettingsScreen` alongside existing hotkeys.
- Registered in `_registerHotkeys` → dispatched via `_handleHotkey('command_palette')` → calls `_openCommandPalette()`.

---

## Files Changed

| File | Change |
|---|---|
| `app/lib/widgets/command_palette.dart` | **New** — `CommandPaletteDialog`, `CommandItem`, `CommandPaletteSearcher` |
| `app/lib/providers/settings_provider.dart` | Add `command_palette` to default hotkeys (`meta+k` / `ctrl+k`) |
| `app/lib/widgets/hotkey_settings_screen.dart` | Add row for `command_palette` hotkey |
| `app/lib/screens/main_screen.dart` | Add `_openCommandPalette()`, wire into `_handleHotkey` |

---

## Integration Sketch

```dart
// main_screen.dart
void _openCommandPalette() {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => CommandPaletteDialog(
      hosts: context.read<HostProvider>().allHosts,
      sessions: context.read<SessionProvider>().sessions,
      snippets: _snippetsFromPlugin(),
      onNavigate: (section) => setState(() {
        _nav = section;
        _viewingTerminal = false;
      }),
      onConnect: (host) async {
        Navigator.of(context).pop();
        setState(() => _viewingTerminal = true);
        await context.read<SessionProvider>().connect(host);
      },
      onAction: (fn) {
        Navigator.of(context).pop();
        fn();
      },
    ),
  );
}
```

---

## Testing

- **Unit:** `CommandPaletteSearcher` — verify scoring, empty query returns all, zero-score items filtered out.
- **Widget:** type query → list updates; arrow keys → selection moves; Enter → callback fires; Escape → dialog closes.

---

## Out of Scope (this iteration)

- Tunnel / port forward items (P0 backlog)
- Recent commands / history items
- Per-item secondary actions (Tab → detail)
