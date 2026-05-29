# Powerline Fonts Support

**Date:** 2026-05-29  
**Status:** Approved

## Goal

Allow users to select a Powerline-patched terminal font from a dropdown in Settings. Supports 6 bundled fonts and a free-form custom font name for system-installed fonts (e.g. Hack Nerd Font).

---

## Assets & Font Registration

Create `app/assets/fonts/powerline/` and download the following `.ttf` files from [powerline/fonts](https://github.com/powerline/fonts):

| Flutter family name | File |
|---|---|
| `DejaVu Sans Mono for Powerline` | `DejaVu Sans Mono for Powerline.ttf` |
| `Inconsolata for Powerline` | `Inconsolata for Powerline.ttf` |
| `Meslo LG S for Powerline` | `Meslo LG S Regular for Powerline.ttf` |
| `Source Code Pro for Powerline` | `Source Code Pro for Powerline.ttf` |
| `Ubuntu Mono derivative Powerline` | `Ubuntu Mono derivative Powerline.ttf` |
| `Roboto Mono for Powerline` | `Roboto Mono for Powerline.ttf` |

Register each in `pubspec.yaml` under `flutter: fonts:`. Each entry uses one weight (Regular).

---

## Data Model

`SettingsProvider` gains one new field:

```dart
String terminalFont = 'monospace';
```

- Persisted as `SharedPreferences` key `'terminalFont'`
- Default `'monospace'` is backward-compatible — existing users see no change
- Both bundled font names and free-form custom names are stored as-is

`save()` gains a `terminalFont` parameter following the existing pattern.

---

## UI — Settings Screen

In the "Terminal" section of `settings_screen.dart`, add two rows below the existing font size row.

**Row: Terminal Font (dropdown)**

- Items: `monospace` (labelled "System Default") + 6 bundled names + `__custom__` sentinel (labelled "Custom…")
- Selecting any bundled font or System Default saves immediately and hides the custom field
- Selecting "Custom…" shows the custom input row

**Row: Custom Font (conditional)**

- Visible only when the current font value does not match any item in the fixed list (i.e. a custom value is active) or when the user just selected "Custom…"
- TextField for font family name (e.g. `Hack Nerd Font`)
- "Apply" button saves the typed value to `SettingsProvider`
- The dropdown reflects "Custom…" when a custom value is active

---

## Terminal View

`terminal_view.dart` — single change:

```dart
textStyle: TerminalStyle(
  fontSize: settings.fontSize,
  fontFamily: settings.terminalFont,  // was hardcoded 'monospace'
),
```

`xterm` passes `fontFamily` directly to Flutter's `TextStyle`, which resolves bundled fonts first, then system fonts, then falls back gracefully.

---

## Files Changed

| File | Change |
|---|---|
| `app/assets/fonts/powerline/*.ttf` | New — 6 font files |
| `app/pubspec.yaml` | Register fonts under `flutter: fonts:` |
| `app/lib/providers/settings_provider.dart` | Add `terminalFont` field + persist |
| `app/lib/widgets/settings_screen.dart` | Add font dropdown + custom input row |
| `app/lib/widgets/terminal_view.dart` | Use `settings.terminalFont` |

---

## Out of Scope

- Font preview in the dropdown
- Downloading fonts at runtime
- Per-session font overrides
