# Additional Terminal Themes — Design

**Date:** 2026-06-05
**Status:** Approved

## Goal

Expand the bundled terminal theme catalog from 35 to 44 themes by adding nine well-known, publicly documented color schemes, rounding out families the app already ships (Kanagawa, Tokyo Night, Nord, Night Owl) and adding popular standalone schemes.

## New themes

| Theme | Family | Primary source |
|---|---|---|
| Kanagawa Dragon | joins existing Kanagawa (Wave) | rebelot/kanagawa.nvim official extras |
| Kanagawa Lotus | joins existing Kanagawa (Wave) | rebelot/kanagawa.nvim official extras |
| Tokyo Night Day | joins existing Tokyo Night | folke/tokyonight.nvim official extras |
| Nord Light | joins existing Nord | community port (no official terminal light variant) |
| Light Owl | joins existing Night Owl | sdras Night Owl project / community port |
| Flexoki Dark | new | kepano/flexoki official palette |
| Flexoki Light | new | kepano/flexoki official palette |
| Aura | new | daltonmenezes/aura-theme official palette |
| Cyberpunk | new | community scheme port |

Palette sourcing rule: use the theme author's official repo when it ships a
terminal (ANSI-16) mapping; otherwise use the most established community port
(the iTerm2-Color-Schemes collection). Exact hex values are recorded in the
implementation plan.

## Changes

Single code file: `app/lib/theme/terminal_themes.dart`.

- Add nine `TerminalTheme` consts following the existing format (16 ANSI
  colors + `foreground`/`background`/`cursor`/`selection` + 3 search-hit
  colors).
- Insert entries into `kTerminalThemes` next to their family so the picker
  groups related themes: Kanagawa Dragon/Lotus after Kanagawa, Tokyo Night Day
  after Tokyo Night, Nord Light after Nord, Light Owl after Night Owl;
  Flexoki Dark/Light, Aura, and Cyberpunk append at the end.
- Do NOT rename the existing `Kanagawa` entry: theme choice persists by name
  in `SharedPreferences`, so renaming would silently reset users to the
  fallback theme.

Conventions for fields the source palettes don't define (matching existing
themes):

- `selection`: the scheme's selection/highlight color with `0xAA` alpha
  (xterm paints selection on top of text — issue #40 requires
  semi-transparency).
- `searchHitBackground`: the theme's yellow/orange accent.
- `searchHitBackgroundCurrent`: the theme's red accent.
- `searchHitForeground`: the theme's background color.

## UI

None. `ThemePickerButton` and the terminal config panel read
`kTerminalThemes` dynamically.

## Error handling

None new. `terminalThemeByName` already falls back to the first theme for
unknown names.

## Testing

- Existing invariant tests in `app/test/theme/terminal_themes_test.dart`
  iterate over `kTerminalThemes` and automatically cover the new entries
  (semi-transparent selection, etc.).
- Add: theme names are unique; catalog count is 44; each new theme is
  retrievable via `terminalThemeByName`.
