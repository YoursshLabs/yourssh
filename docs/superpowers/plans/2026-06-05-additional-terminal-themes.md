# Additional Terminal Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add nine publicly documented terminal color schemes to the bundled catalog, growing it from 35 to 44 themes.

**Architecture:** Pure data change. Each theme is a `const TerminalTheme` (xterm package) in `app/lib/theme/terminal_themes.dart`, registered in the `kTerminalThemes` list. The theme picker and terminal config panel read that list dynamically, so no UI changes. Palette hex values were researched from each theme author's official repo (kanagawa.nvim extras, tokyonight.nvim extras, kepano/flexoki, daltonmenezes/aura-theme) with the iTerm2-Color-Schemes collection as fallback for schemes without an official terminal port (Nord Light, Light Owl, Cyberpunk).

**Tech Stack:** Flutter, xterm `TerminalTheme`, flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-05-additional-terminal-themes-design.md`

**Working directory:** all commands run from `app/` inside the repo.

**Conventions applied to every new theme** (same as existing entries):
- `selection` = the scheme's selection color with `0xAA` alpha (xterm draws selection above text; must be semi-transparent — issue #40, enforced by an existing test)
- `searchHitBackground` = the theme's yellow/orange accent
- `searchHitBackgroundCurrent` = the theme's red accent
- `searchHitForeground` = the theme's background

---

### Task 1: Nine new themes + registry entries + tests

**Files:**
- Modify: `app/lib/theme/terminal_themes.dart` (entries list ~lines 10–46; consts appended at end of file)
- Test: `app/test/theme/terminal_themes_test.dart`

- [ ] **Step 1: Add failing tests**

Append inside `main()` in `app/test/theme/terminal_themes_test.dart`:

```dart
  test('theme names are unique', () {
    final names = kTerminalThemes.map((e) => e.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('catalog contains the nine added themes', () {
    expect(kTerminalThemes.length, 44);
    const added = [
      'Kanagawa Dragon',
      'Kanagawa Lotus',
      'Tokyo Night Day',
      'Nord Light',
      'Light Owl',
      'Flexoki Dark',
      'Flexoki Light',
      'Aura',
      'Cyberpunk',
    ];
    for (final name in added) {
      expect(kTerminalThemeNames, contains(name));
    }
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/theme/terminal_themes_test.dart`
Expected: FAIL — catalog has 35 themes and the added names are missing.

- [ ] **Step 3: Register the new entries in `kTerminalThemes`**

In `app/lib/theme/terminal_themes.dart`, make these insertions in the `kTerminalThemes` list:

After `TerminalThemeEntry('Tokyo Night', _tokyoNight),`:

```dart
  TerminalThemeEntry('Tokyo Night Day', _tokyoNightDay),
```

After `TerminalThemeEntry('Nord', _nord),`:

```dart
  TerminalThemeEntry('Nord Light', _nordLight),
```

After `TerminalThemeEntry('Night Owl', _nightOwl),`:

```dart
  TerminalThemeEntry('Light Owl', _lightOwl),
```

After `TerminalThemeEntry('Kanagawa', _kanagawa),`:

```dart
  TerminalThemeEntry('Kanagawa Dragon', _kanagawaDragon),
  TerminalThemeEntry('Kanagawa Lotus', _kanagawaLotus),
```

After `TerminalThemeEntry('Atom One Light', _atomOneLight),` (last entry):

```dart
  TerminalThemeEntry('Flexoki Dark', _flexokiDark),
  TerminalThemeEntry('Flexoki Light', _flexokiLight),
  TerminalThemeEntry('Aura', _aura),
  TerminalThemeEntry('Cyberpunk', _cyberpunk),
```

- [ ] **Step 4: Append the nine theme consts at the end of the file**

```dart
// ── Kanagawa Dragon ───────────────────────────────────────
// Source: rebelot/kanagawa.nvim extras (alacritty/kanagawa_dragon.toml)
const _kanagawaDragon = TerminalTheme(
  cursor: Color(0xFFC8C093),
  selection: Color(0xAA2D4F67),
  foreground: Color(0xFFC5C9C5),
  background: Color(0xFF181616),
  black: Color(0xFF0D0C0C),
  red: Color(0xFFC4746E),
  green: Color(0xFF8A9A7B),
  yellow: Color(0xFFC4B28A),
  blue: Color(0xFF8BA4B0),
  magenta: Color(0xFFA292A3),
  cyan: Color(0xFF8EA4A2),
  white: Color(0xFFC8C093),
  brightBlack: Color(0xFFA6A69C),
  brightRed: Color(0xFFE46876),
  brightGreen: Color(0xFF87A987),
  brightYellow: Color(0xFFE6C384),
  brightBlue: Color(0xFF7FB4CA),
  brightMagenta: Color(0xFF938AA9),
  brightCyan: Color(0xFF7AA89F),
  brightWhite: Color(0xFFC5C9C5),
  searchHitBackground: Color(0xFFE6C384),
  searchHitBackgroundCurrent: Color(0xFFE46876),
  searchHitForeground: Color(0xFF181616),
);

// ── Kanagawa Lotus ────────────────────────────────────────
// Source: rebelot/kanagawa.nvim extras (alacritty/kanagawa_lotus.toml)
const _kanagawaLotus = TerminalTheme(
  cursor: Color(0xFF43436C),
  selection: Color(0xAAC9CBD1),
  foreground: Color(0xFF545464),
  background: Color(0xFFF2ECBC),
  black: Color(0xFF1F1F28),
  red: Color(0xFFC84053),
  green: Color(0xFF6F894E),
  yellow: Color(0xFF77713F),
  blue: Color(0xFF4D699B),
  magenta: Color(0xFFB35B79),
  cyan: Color(0xFF597B75),
  white: Color(0xFF545464),
  brightBlack: Color(0xFF8A8980),
  brightRed: Color(0xFFD7474B),
  brightGreen: Color(0xFF6E915F),
  brightYellow: Color(0xFF836F4A),
  brightBlue: Color(0xFF6693BF),
  brightMagenta: Color(0xFF624C83),
  brightCyan: Color(0xFF5E857A),
  brightWhite: Color(0xFF43436C),
  searchHitBackground: Color(0xFF77713F),
  searchHitBackgroundCurrent: Color(0xFFC84053),
  searchHitForeground: Color(0xFFF2ECBC),
);

// ── Tokyo Night Day ───────────────────────────────────────
// Source: folke/tokyonight.nvim extras (alacritty/tokyonight_day.toml)
const _tokyoNightDay = TerminalTheme(
  cursor: Color(0xFF3760BF),
  selection: Color(0xAA99A7DF),
  foreground: Color(0xFF3760BF),
  background: Color(0xFFE1E2E7),
  black: Color(0xFFB4B5B9),
  red: Color(0xFFF52A65),
  green: Color(0xFF587539),
  yellow: Color(0xFF8C6C3E),
  blue: Color(0xFF2E7DE9),
  magenta: Color(0xFF9854F1),
  cyan: Color(0xFF007197),
  white: Color(0xFF6172B0),
  brightBlack: Color(0xFFA1A6C5),
  brightRed: Color(0xFFFF4774),
  brightGreen: Color(0xFF5C8524),
  brightYellow: Color(0xFFA27629),
  brightBlue: Color(0xFF358AFF),
  brightMagenta: Color(0xFFA463FF),
  brightCyan: Color(0xFF007EA8),
  brightWhite: Color(0xFF3760BF),
  searchHitBackground: Color(0xFF8C6C3E),
  searchHitBackgroundCurrent: Color(0xFFF52A65),
  searchHitForeground: Color(0xFFE1E2E7),
);

// ── Nord Light ────────────────────────────────────────────
// Source: iTerm2-Color-Schemes port (no official Nord light terminal theme)
const _nordLight = TerminalTheme(
  cursor: Color(0xFF7BB3C3),
  selection: Color(0xAAD8DEE9),
  foreground: Color(0xFF414858),
  background: Color(0xFFE5E9F0),
  black: Color(0xFF3B4252),
  red: Color(0xFFBF616A),
  green: Color(0xFF96B17F),
  yellow: Color(0xFFC5A565),
  blue: Color(0xFF81A1C1),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF7BB3C3),
  white: Color(0xFFA5ABB6),
  brightBlack: Color(0xFF4C566A),
  brightRed: Color(0xFFBF616A),
  brightGreen: Color(0xFF96B17F),
  brightYellow: Color(0xFFC5A565),
  brightBlue: Color(0xFF81A1C1),
  brightMagenta: Color(0xFFB48EAD),
  brightCyan: Color(0xFF82AFAE),
  brightWhite: Color(0xFFECEFF4),
  searchHitBackground: Color(0xFFC5A565),
  searchHitBackgroundCurrent: Color(0xFFBF616A),
  searchHitForeground: Color(0xFFE5E9F0),
);

// ── Light Owl ─────────────────────────────────────────────
// Source: iTerm2-Color-Schemes port of Sarah Drasner's Light Owl
const _lightOwl = TerminalTheme(
  cursor: Color(0xFF403F53),
  selection: Color(0xAAE0E0E0),
  foreground: Color(0xFF403F53),
  background: Color(0xFFFBFBFB),
  black: Color(0xFF403F53),
  red: Color(0xFFDE3D3B),
  green: Color(0xFF08916A),
  yellow: Color(0xFFE0AF02),
  blue: Color(0xFF288ED7),
  magenta: Color(0xFFD6438A),
  cyan: Color(0xFF2AA298),
  white: Color(0xFFBDBDBD),
  brightBlack: Color(0xFF989FB1),
  brightRed: Color(0xFFDE3D3B),
  brightGreen: Color(0xFF08916A),
  brightYellow: Color(0xFFDAAA01),
  brightBlue: Color(0xFF288ED7),
  brightMagenta: Color(0xFFD6438A),
  brightCyan: Color(0xFF2AA298),
  brightWhite: Color(0xFFF0F0F0),
  searchHitBackground: Color(0xFFE0AF02),
  searchHitBackgroundCurrent: Color(0xFFDE3D3B),
  searchHitForeground: Color(0xFFFBFBFB),
);

// ── Flexoki Dark ──────────────────────────────────────────
// Source: kepano/flexoki official palette
const _flexokiDark = TerminalTheme(
  cursor: Color(0xFFCECDC3),
  selection: Color(0xAA403E3C),
  foreground: Color(0xFFCECDC3),
  background: Color(0xFF100F0F),
  black: Color(0xFF100F0F),
  red: Color(0xFFD14D41),
  green: Color(0xFF879A39),
  yellow: Color(0xFFD0A215),
  blue: Color(0xFF4385BE),
  magenta: Color(0xFFCE5D97),
  cyan: Color(0xFF3AA99F),
  white: Color(0xFF878580),
  brightBlack: Color(0xFF575653),
  brightRed: Color(0xFFAF3029),
  brightGreen: Color(0xFF66800B),
  brightYellow: Color(0xFFAD8301),
  brightBlue: Color(0xFF205EA6),
  brightMagenta: Color(0xFFA02F6F),
  brightCyan: Color(0xFF24837B),
  brightWhite: Color(0xFFCECDC3),
  searchHitBackground: Color(0xFFD0A215),
  searchHitBackgroundCurrent: Color(0xFFD14D41),
  searchHitForeground: Color(0xFF100F0F),
);

// ── Flexoki Light ─────────────────────────────────────────
// Source: kepano/flexoki official palette
const _flexokiLight = TerminalTheme(
  cursor: Color(0xFF100F0F),
  selection: Color(0xAACECDC3),
  foreground: Color(0xFF100F0F),
  background: Color(0xFFFFFCF0),
  black: Color(0xFF100F0F),
  red: Color(0xFFAF3029),
  green: Color(0xFF66800B),
  yellow: Color(0xFFAD8301),
  blue: Color(0xFF205EA6),
  magenta: Color(0xFFA02F6F),
  cyan: Color(0xFF24837B),
  white: Color(0xFF6F6E69),
  brightBlack: Color(0xFFB7B5AC),
  brightRed: Color(0xFFD14D41),
  brightGreen: Color(0xFF879A39),
  brightYellow: Color(0xFFD0A215),
  brightBlue: Color(0xFF4385BE),
  brightMagenta: Color(0xFFCE5D97),
  brightCyan: Color(0xFF3AA99F),
  brightWhite: Color(0xFFCECDC3),
  searchHitBackground: Color(0xFFAD8301),
  searchHitBackgroundCurrent: Color(0xFFAF3029),
  searchHitForeground: Color(0xFFFFFCF0),
);

// ── Aura ──────────────────────────────────────────────────
// Source: daltonmenezes/aura-theme official windows-terminal port.
// Aura's official ANSI mapping intentionally reuses accents
// (blue=green, cyan=white) — kept as the author published it.
const _aura = TerminalTheme(
  cursor: Color(0xFFA277FF),
  selection: Color(0xAAA394F0),
  foreground: Color(0xFFEDECEE),
  background: Color(0xFF15141B),
  black: Color(0xFF110F18),
  red: Color(0xFFFF6767),
  green: Color(0xFF61FFCA),
  yellow: Color(0xFFFFCA85),
  blue: Color(0xFF61FFCA),
  magenta: Color(0xFFA277FF),
  cyan: Color(0xFFEDECEE),
  white: Color(0xFFEDECEE),
  brightBlack: Color(0xFF4D4D4D),
  brightRed: Color(0xFFFFCA85),
  brightGreen: Color(0xFFA277FF),
  brightYellow: Color(0xFFFFCA85),
  brightBlue: Color(0xFFA277FF),
  brightMagenta: Color(0xFFA277FF),
  brightCyan: Color(0xFF61FFCA),
  brightWhite: Color(0xFFEDECEE),
  searchHitBackground: Color(0xFFFFCA85),
  searchHitBackgroundCurrent: Color(0xFFFF6767),
  searchHitForeground: Color(0xFF15141B),
);

// ── Cyberpunk ─────────────────────────────────────────────
// Source: iTerm2-Color-Schemes port
const _cyberpunk = TerminalTheme(
  cursor: Color(0xFF21F6BC),
  selection: Color(0xAAC1DEFF),
  foreground: Color(0xFFE5E5E5),
  background: Color(0xFF332A57),
  black: Color(0xFF000000),
  red: Color(0xFFFF7092),
  green: Color(0xFF00FBAC),
  yellow: Color(0xFFFFFA6A),
  blue: Color(0xFF00BFFF),
  magenta: Color(0xFFDF95FF),
  cyan: Color(0xFF86CBFE),
  white: Color(0xFFFFFFFF),
  brightBlack: Color(0xFF595959),
  brightRed: Color(0xFFFF8AA4),
  brightGreen: Color(0xFF21F6BC),
  brightYellow: Color(0xFFFFF787),
  brightBlue: Color(0xFF1BCCFD),
  brightMagenta: Color(0xFFE6AEFE),
  brightCyan: Color(0xFF99D6FC),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFA6A),
  searchHitBackgroundCurrent: Color(0xFFFF7092),
  searchHitForeground: Color(0xFF332A57),
);
```

- [ ] **Step 5: Run theme tests to verify they pass**

Run: `cd app && flutter test test/theme/terminal_themes_test.dart`
Expected: ALL PASS — including the pre-existing invariant tests (semi-transparent selection) now iterating over 44 themes.

- [ ] **Step 6: Analyze and run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/theme/terminal_themes.dart app/test/theme/terminal_themes_test.dart
git commit -m "feat(terminal): add nine terminal themes (Kanagawa Dragon/Lotus, Tokyo Night Day, Nord Light, Light Owl, Flexoki, Aura, Cyberpunk)"
```

---

### Task 2: Manual smoke check (optional)

- [ ] **Step 1: Run the app**

Run: `cd app && flutter run -d macos`

Verify:
1. Open the terminal config panel (tune icon) → theme picker lists the nine new themes next to their families (Kanagawa group, Tokyo Night group, Nord group, Night Owl group).
2. Select Kanagawa Lotus and Flexoki Light → light backgrounds render with readable foreground.
3. Select Cyberpunk → selection highlight and search hits remain readable.
