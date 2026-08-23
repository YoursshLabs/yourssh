# Mobile UI Redesign — Termius-style (Android)

**Date:** 2026-06-25
**Branch:** `feat/android-mobile-app`
**Status:** Approved design

## Problem

The Android/mobile build (`app/lib/mobile/`) already has the right *structure* — a
bottom-nav shell with Hosts / Sessions / SFTP / Settings, an accessory key bar,
a snippets sheet, and pinch-to-zoom. But the *presentation* and *ergonomics* fall
short of a polished mobile SSH client:

- Hosts are plain `ListTile` rows (grey icon + two text lines + chevron).
- Session switching is a bare `ChoiceChip` strip; there is no consolidated
  side panel for keys / snippets / history / themes.
- The accessory bar is flat and ungrouped; cursor movement relies on the OS
  keyboard's arrow keys only (no terminal touch gestures).
- SFTP / Settings use generic Material widgets with no shared visual language.

Goal: bring the mobile UI up to a Termius-class look **and** feel — across all four
screens — without rebuilding navigation or touching the connection/provider logic.

## Reference design language (Termius mobile)

- Bottom tab bar for single-handed reach (we already have this).
- Host list with a colored avatar (initials), status dot, and tag badges.
- Terminal with a grouped keyboard-accessory bar and a side panel exposing
  Extended Keyboard / Snippets / Command History / Themes.
- Touch gestures: long-press + drag to move the cursor, double-tap for Tab,
  pinch to zoom.

## Non-goals (YAGNI)

- No new navigation paradigm or custom nav bar — keep Material `NavigationBar`.
- No changes to `SshService`, providers, sync, app-lock, or TOFU logic.
- No iPad/foldable/tablet multi-pane layout in this pass (phone layout only).
- No new desktop theming — desktop `buildAppTheme()` is untouched; mobile gets
  an additive token layer.
- No RDP on mobile.

## Approach

**Refine in place + introduce a mobile design system.** Keep every provider,
service, and navigation wiring. Add a small mobile token/widget layer and reskin
each screen on top of it. This reuses all existing logic, minimizes regression
risk, and still delivers the Termius look and the gesture/side-panel ergonomics.

Rejected alternatives:
- *Rebuild the mobile shell* (custom nav, hand-drawn widgets): higher regression
  risk, diverges from Material, slower — not justified.
- *Theme-only* (colors + typography): cheapest but does not fix the ergonomics
  ("không tiện dùng"), so it fails the brief.

## Architecture

```
app/lib/mobile/
├── theme/
│   └── mobile_tokens.dart          # NEW — spacing, radii, sizes, durations
├── widgets/                        # NEW — shared, isolated, unit-testable
│   ├── host_avatar.dart            # seeded-color rounded avatar w/ initials
│   ├── status_dot.dart             # connection-state dot
│   ├── tag_chip.dart               # compact tag badge
│   ├── section_header.dart         # uppercase letter-spaced header
│   └── mobile_card.dart            # shared card container styling
├── screens/                        # reskinned (logic unchanged)
│   ├── mobile_hosts_screen.dart
│   ├── mobile_sessions_screen.dart
│   ├── mobile_sftp_screen.dart
│   ├── mobile_settings_screen.dart
│   └── mobile_add_host_screen.dart
└── terminal/
    ├── accessory_key_bar.dart      # regrouped keys + extended-kbd trigger
    ├── terminal_side_panel.dart    # NEW — bottom-sheet: Keys/Snippets/History/Themes
    └── terminal_cursor_gestures.dart  # NEW — pure gesture→key mapping
```

Shared widgets depend only on `AppColors` (`app/lib/theme/app_theme.dart`) and
`mobile_tokens.dart`. No widget reaches into providers — screens pass data in.

## Design tokens (`mobile_tokens.dart`)

A plain Dart class of constants (no Flutter context needed):

- **Spacing:** `space1=4, space2=8, space3=12, space4=16, space5=24`.
- **Radii:** `radiusCard=14, radiusPill=22, radiusAvatar=12`.
- **Sizes:** `avatar=44, statusDot=8, accessoryBarHeight=48, touchTarget=44`.
- **Durations:** `tap=120ms`, `panel=220ms`.

Colors continue to come from `AppColors`. Accent stays green `#22C55E` as the
primary; per-host **seed colors** (existing `hostColorSeed(hostname)` in
`app_theme.dart`) drive avatar backgrounds only, so lists feel varied without a
second accent system.

## Shared widgets

- **`HostAvatar`** — rounded square (`radiusAvatar`, size `avatar`). Background =
  `hostColorSeed(host)` at ~18% opacity; foreground = up to two initials in the
  full-strength seed color, weight 600. Falls back to a `dns`/`terminal` glyph
  when the label has no letters. Optional small protocol glyph in a corner
  (SSH default; future-proofed but RDP is desktop-only).
- **`StatusDot`** — `statusDot`-sized circle. Green (`AppColors.accent`) =
  connected, amber (`AppColors.orange`) = connecting, grey
  (`AppColors.textTertiary`) = offline. Takes a `SessionStatus`-derived enum so
  it has no provider dependency.
- **`TagChip`** — compact pill, `card`+border background, `textSecondary` label,
  11px. Used for host tags and filter chips.
- **`SectionHeader`** — uppercase, letter-spaced (0.8), 11px, `textTertiary`.
- **`MobileCard`** — `AppColors.card` background, `radiusCard`, 1px `border`,
  `space3` padding, `InkWell` ripple; the single source of card styling.

## Screen designs

### 1. Hosts (`mobile_hosts_screen.dart`)

- **Search**: pill-shaped field (leading search icon, `radiusPill`), still backed
  by `HostQuery.parse()`.
- **Filter chips**: a horizontally-scrolling `TagChip` row of the distinct tags
  across saved hosts; tapping one appends/removes a `tag:` term in the query.
  Hidden when there are no tags.
- **Host rows**: `HostCard` = `MobileCard` containing `HostAvatar` + label
  (15px/600) + `user@host:port` (12px `textSecondary`) + `TagChip`s + `StatusDot`
  + trailing chevron. Tap → `connectAny()` then switch to Sessions (unchanged).
- **Swipe / long-press**: `Dismissible`-style trailing swipe reveals Edit +
  Delete; long-press opens a menu (Connect / Edit / Duplicate / Delete). Delete
  confirms. These call existing `HostProvider` methods.
- **Empty state**: centered icon + "No hosts yet" + a primary "Add host" button
  (in addition to the FAB).

### 2. Sessions / Terminal (`mobile_sessions_screen.dart`)

- **App bar**: host label + `StatusDot`; overflow menu = Rename / Disconnect /
  Open side panel (Themes tab).
- **Session tabs**: pill tabs (replace `ChoiceChip`) — each shows a host-color
  dot + label + a close ×; a trailing "+" opens the host picker. Active pill uses
  `accent` border.
- **Side panel** (`terminal_side_panel.dart`): a draggable bottom sheet with a
  4-tab segmented control — **Keys** (full extended-keyboard grid), **Snippets**
  (reuses the existing snippets sheet content, tap to insert), **History**
  (per-host command history from `CommandHistoryProvider`, tap to insert/run),
  **Themes** (`TerminalAppearanceControls`, applied per session/host).
- **Accessory bar** (`accessory_key_bar.dart`): regroup into Esc · Tab · arrows ·
  Ctrl/Alt (armed-state highlight via `accent`) · ^C/^D · symbols, plus a button
  that opens the side panel on the Keys tab. One-shot modifier semantics
  preserved (`accessory_bar_controller.dart` unchanged).
- **Cursor gestures** (`terminal_cursor_gestures.dart`, pure mapping):
  - long-press + drag → arrow keys in the drag direction, with up to 3
    acceleration gears the longer the drag persists;
  - double-tap → Tab;
  - pinch → zoom (existing behavior retained).
  The widget translates gestures into key bytes; the screen feeds them to the
  session's input sink. Mapping logic is pure for unit testing.

### 3. SFTP (`mobile_sftp_screen.dart`)

- **Breadcrumb path bar** at top (tap a crumb to jump up the tree).
- **File rows**: type-aware leading icon (folder / file / symlink / archive),
  name, and a `textSecondary` size · modified-date subtitle, styled via
  `MobileCard`-consistent rows.
- **Toolbar**: upload / new-folder / refresh as compact icon buttons.
- **Transfer progress**: a slim progress strip when an upload/download is active,
  fed by the existing transfer state.

### 4. Settings (`mobile_settings_screen.dart`)

- Group into labeled sections (`SectionHeader`) inside cards: **Terminal**
  (appearance), **Sync** (cloud config + P2P QR import), **Security** (app-lock),
  **About**. Each row gets a leading icon and consistent spacing. Functionality
  (sync, P2P, app-lock, appearance) is unchanged.

### Add host (`mobile_add_host_screen.dart`)

Reskin the form to the token system (section headers, consistent field styling,
a clearer primary save button). No field/logic changes.

## Error handling

Reskinning only; existing error paths are preserved:
- Connect failures still surface via the Sessions screen status + error message.
- SFTP errors keep their current snackbar/state handling.
- Gesture mapping never throws — unmapped gestures are no-ops; out-of-range
  acceleration clamps to gear 1.

## Testing

Pure/unit + widget tests (no device required):

- `host_avatar` — initials extraction, glyph fallback, seeded color determinism.
- `status_dot` — status→color mapping.
- `terminal_cursor_gestures` — drag direction → arrow bytes, acceleration gear
  clamping, double-tap → Tab.
- `accessory_key_bar` — grouped layout renders, armed-modifier one-shot behavior.
- `mobile_hosts_screen` — `HostCard` renders label/subtitle/tags/status; tap
  triggers connect; swipe reveals edit/delete.
- Existing mobile tests must continue to pass.

## Implementation order (milestones)

1. **Design system**: `mobile_tokens.dart` + shared widgets + their tests.
2. **Hosts**: `HostCard`, search/filter, swipe/long-press, empty state.
3. **Terminal ergonomics**: accessory-bar regroup, side panel, cursor gestures.
4. **SFTP**: breadcrumb + file rows + transfer strip.
5. **Settings + Add host**: sectioned reskin.

Each milestone is independently shippable and leaves the app buildable.
