# YourSSH UI redesign with forui ("Amber Brand") — design

Date: 2026-11-12 · Status: proposed. The owner chose direction **B — Amber Brand** from a forui spike and delegated the remaining decisions.

Reference mockups, rendered by the spike with forui 0.27.7, are in `assets/ui-redesign/`:
- `overview-B.png`
- `B-1-hosts.png`
- `B-2-terminal.png`
- `B-3-sftp.png`
- `B-4-settings.png`
- `B-5-mobile.png`

They are the visual target. They are not pixel-exact contracts.

## Intent

The owner finds every screen of the app unattractive and inconsistent across platforms. Today:
- Most UI is hand-made Material widgets themed by `AppColors`, with a green accent.
- Mobile has its own `MobileColors`/`MobileTokens`.
- Spacing, radii, typography and controls differ screen to screen.

The goal is one design system, built on [forui](https://github.com/duobaseio/forui), that makes YourSSH look like a polished professional tool. It must look the same on macOS, Windows, Linux, Android and iOS, with the amber brand colour of the app icon as its accent.

## Goals

1. Every desktop and mobile screen uses one set of tokens (colours, spacing, radii, type) and forui components. Where forui has no component, a small set of YourSSH components is built on those same tokens.
2. The B look: dark, warm stone neutrals, amber primary on actions and active states, Inter for UI text, and the existing monospace fonts for terminal and code.
3. Identical rendering on all five platforms. Fonts are bundled, not taken from the OS.
4. The app stays shippable after every phase. Unmigrated screens already pick up the new palette from phase 0.

## Non-goals

- No new features or flows. This is a visual and structural reskin. Navigation, information architecture and behaviour stay as they are, except for the small layout changes visible in the mockups: the host detail panel on the right, and the status bar.
- No light theme. The app is dark-only (`ThemeMode.dark`) and stays so. Direction C was not chosen.
- No change to terminal emulation or rendering. `TerminalView`, the glyph atlas and the terminal theme catalog are untouched, apart from a new default terminal theme matching the surface colour.
- No redesign of RDP/VNC remote canvases. Only their surrounding chrome changes.

## Anti-goals (failures even if it "works")

- Terminal throughput or frame time regresses. The `terminal_perf_test` numbers from v0.3.0 must stay within ±5%.
- Any feature becomes unreachable, or loses keyboard access, a shortcut, a tooltip or a semantics label it had before.
- Text contrast below WCAG AA (4.5:1 for body text, 3:1 for large text and UI glyphs) on the new palette.
- A half-migrated screen that mixes old green-accent Material controls with new amber forui controls in a visible way.
- The UI font is fetched over the network at runtime.

## Constraints

- forui 0.27.x needs Flutter ≥ 3.47.0 and Dart ≥ 3.13.
  - CI pins Flutter **3.47.1**, so `app/pubspec.yaml` `environment.sdk` rises from `^3.12.0` to `^3.13.0`. The spike only built on 3.50, so phase 0's first step is a CI build on 3.47.1.
  - forui pulls in `material_ui` 1.11, which needs Flutter ≥ 3.47.
- forui runs inside the existing `MaterialApp`, so migration can go screen by screen. Material stays as the app root.
- About 117 of 261 files under `app/lib` import Material. The largest groups:

  | Widget | Count |
  |---|---|
  | `IconButton` | 88 |
  | `TextButton` | 75 |
  | `TextField` | 49 |
  | `ScaffoldMessenger`/`SnackBar` | 48 |
  | `ListTile` | 36 |
  | `AlertDialog` | 34 |
  | `DropdownButton` | 24 |

- Widget tests that find Material widget types must be updated in the same phase as their screen.

## Design system

### Tokens: `app/lib/theme/ys_theme.dart`

`YsTheme` is the single source of truth. It builds the forui `FThemeData` and exposes the extra slots that forui's colour set lacks. `AppColors` and `MobileColors` become thin aliases onto it in phase 0, so unmigrated screens recolour at once. Both are deleted at the end.

| Token | Value | Use |
|---|---|---|
| background | `#0D0C0A` | page canvas |
| card | `#161412` | cards, panels |
| secondary / muted | `#26231F` | inputs, chips, hover |
| foreground | `#F5F5F4` | primary text |
| mutedForeground | `#A8A29E` | secondary text |
| border | `#FFEBD2` @ 12% | hairlines |
| primary (amber) | `#F3A231` | primary buttons, active tab/nav, focus ring, switches on |
| primaryForeground | `#141416` | text on amber |
| accentText | `#FFC85A` | amber text and links on dark |
| chrome | `#080706` | top tab bar, status bar |
| sidebar | `#110F0D` | left nav |
| terminalSurface | `#0E0C0A` | terminal background (new default terminal theme "YourSSH Amber") |
| status ok / warn / off / error | `#22C55E` / `#EAB308` / `#71717A` / `#EF4444` | health dots, toasts |

Spacing is a 4-px scale: 4, 8, 12, 16, 24, 32. Radii are 6 for controls, 10 for cards, 14 for mobile cards. Session tab colours and host avatar colours keep their existing palettes; they are user data.

### Typography

- UI text uses **Inter**, bundled as an asset under `assets/fonts/inter/` (OFL). The type scale is forui's.
- Terminal and code fonts are unchanged: the bundled Nerd/Powerline families plus the user's choice.
- `google_fonts` must not be used for UI text, because it fetches at runtime.

### Icons

Use forui's Lucide set (`FLucideIcons`) everywhere. Material `Icons.*` are replaced screen by screen. OS and distro glyphs keep the existing SVG assets.

### Components

- **Straight from forui:**
  - `FScaffold`
  - `FSidebar` and its group and item widgets
  - `FCard`
  - `FBadge`
  - `FButton` and `FButton.icon`
  - `FTextField`
  - `FSelect`
  - `FSwitch`
  - `FTabs` (segmented, e.g. SSH/RDP)
  - `FTileGroup`/`FTile`
  - `FBreadcrumb`
  - `FResizable`
  - `FDeterminateProgress`
  - `FDialog`
  - `FToaster`/toasts
  - `FPopover`/`FPopoverMenu`
  - `FTooltip`
  - `FHeader`
  - `FBottomNavigationBar`

- **YourSSH components**, built on `YsTheme` because forui has no equivalent:
  - `YsSessionTabBar` — browser-style top tabs: pinned Home/SFTP, session tabs with a health dot, a colour tag, close, drag-reorder, overflow and keyboard navigation.
  - `YsStatusBar` — the bottom terminal status line.
  - `YsFileTable` — the SFTP list: sortable columns, multi-select, drag and drop, keyboard.
  - `YsHostCard` — host card with OS tile, health dot, tags and connect.
  - `YsOsTile`
  - `YsSectionHeader`
  - `YsEmptyState`

### Where the design system lives

New package **`packages/yourssh_ui`** (Flutter, depends on forui) holds:
- `YsTheme` and its tokens
- the `Ys*` components
- an export of forui

The app and the plugin packages (`yourssh_snippets`, `yourssh_devops`, `yourssh_web_tools`) all import it. Plugin screens therefore use the same system, and nothing stays half-migrated.

The token table above lives in `packages/yourssh_ui/lib/src/ys_theme.dart`. `app/lib/theme/app_theme.dart` re-exports and aliases it until the clean-up.

### Mockups vs. real data

The mockups are illustrative. Only what the app already knows is built.

- **Kept** (data exists):
  - Host status dot.
  - Open-session count per host, derived from `SessionProvider`.
  - Tags, filter chips and the "x of N hosts" count from the current search and tag filter.
  - Sort options the dashboard already has.
  - tmux and cwd chips, when shell integration or tmux supplies them.
- **Omitted** (no new measurement code in this project):
  - Latency.
  - Throughput.
  - The "lag 4.2 s" tag.
  - The "degraded" count.
- **Terminal status bar**, by session type:

  | Session | Shows |
  |---|---|
  | SSH | connection status, `user@host`, the jump chain ("via …"), agent-forwarding state, TERM, cols × rows, and recording indicator + elapsed time |
  | Local PTY | shell + cols × rows |
  | RDP/VNC | resolution + status |

### Known forui gotchas from the spike (builders must handle these)

- `FSwitch` with a label inside a `Row` wraps one letter per line. Give it bounded width or put the label outside.
- `FHeader` adds its own top safe area. Don't double it.
- `FButton` stretches by default. Use `mainAxisSize: min` in rows.
- Text outside Material widgets needs a `DefaultTextStyle`.
- Selected `FSidebar` items need a style delta to take the amber accent. Do this once, in `YsTheme`.

## Phasing

Each phase is its own PR into `develop` with passing CI. Releases may go out between phases.

| Phase | Scope |
|---|---|
| **0 · Foundation** | forui dependency and SDK bump, verified on CI's Flutter 3.47.1. `YsTheme` plus `FTheme` at the root. Inter bundled. `AppColors`/`MobileColors` aliased to the new tokens, so the whole app turns amber/stone at once. "YourSSH Amber" terminal theme (new; the existing "YourSSH Dark" theme is kept unchanged) as the default for new installs; existing installs keep their current theme, including the implicit "Dracula" default. Screenshot harness updated. |
| **1 · Shell** | Left sidebar → `FSidebar`. Top tab bar → `YsSessionTabBar`. Global sweep of toasts (`ScaffoldMessenger`/`SnackBar` → `FToaster`), dialogs (`AlertDialog` → `FDialog`), tooltips and context menus. |
| **2 · Hosts** | Hosts dashboard (search, tag filter chips, groups, `YsHostCard` grid/list), `HostDetailPanel` editor, import panel, keychain picker. |
| **3 · Terminal workspace** | Terminal frame and split chrome, `WorkspaceSidePanel` (snippets, terminal config), input bar, broadcast/bulk-run bars, `YsStatusBar`, terminal context menu. Perf check against v0.3.0. |
| **4 · SFTP** | Dual panel with `FBreadcrumb` and `FResizable`, `YsFileTable`, transfer queue, built-in editor chrome. |
| **5 · Remaining desktop screens** | Settings (all sections), port forwarding, known hosts, recordings, audit log, plugins manager and console, AI chat, RDP/VNC chrome, onboarding, sync and pairing. Plugin packages' own screens (Snippets, DevOps: containers, network tools, Cloudflare tunnel, mail catcher, MCP, S3; Web Tools). The Monaco editor gets a matching custom dark theme (background, selection, cursor and gutter from the tokens). |
| **6 · Mobile** | Restyle the existing mobile structure (`mobile_home_shell`, its tabs, the session chips and `accessory_key_bar`) with the same tokens and forui components. The tab set and navigation do **not** change; `B-5-mobile.png` shows the look, not new navigation. |

After phase 6:
- Delete `AppColors`, `MobileColors`/`MobileTokens` and the leftover Material-only widgets.
- A lint check (`custom_lint` rule or a CI grep) bans new `IconButton`/`AlertDialog`/`SnackBar`/`Icons.` uses under `app/lib/` and the plugin packages. Uses inside `packages/yourssh_ui` are allowed.

## Verification

- **Visual:** the macOS screenshot integration tests (`app/integration_test/feature_screenshots_test.dart`, `mobile_screenshots_test.dart`) render each migrated screen. The PR attaches the new PNGs next to the matching spike mockup, and the README screenshots are refreshed after phase 6.
- **Behavioural:** the full `flutter test` stays green. Tests that relied on Material finders are rewritten to find by key, text or semantics, not by widget type.
- **Performance:** in phase 3, `terminal_perf_test` (plain, color, unicode, tui corpora) stays within ±5% of the v0.3.0 numbers.
- **Accessibility:**
  - Tab-order and focus traversal checks on each migrated screen.
  - Every icon-only button has a tooltip and a semantics label.
  - The contrast pairs in the token table are checked by a unit test.
- **Merge gate per phase:**
  - CI green.
  - Screenshots of every screen the phase touched, next to the matching mockup, attached to the PR and sent to the owner.
  - The PR merges into `develop` after the owner OKs the screenshots.
- **Cross-platform:** CI builds macOS, Windows, Linux, Android and iOS (once the iOS work lands). Manual spot checks on each desktop OS after phases 1 and 3.

## Toolchain fallback

If forui 0.27.x does not build on Flutter 3.47.1:
1. Use the newest forui release that does.
2. Bumping the CI/release Flutter pin is **not** part of this project. It belongs to the separate Flutter 3.50 migration, which needs the Gradle, AGP and Kotlin bumps. Stop and report if no forui release builds on 3.47.1.

## Ordering with other work

The order, which is the builder's call (the owner can reorder):
1. Finish CLI phase 1, which is in progress.
2. This redesign, phases 0–6.
3. iOS phase 1, so iOS ships with the new look instead of being tested twice.

## Decided here (owner delegated these)

- Direction B (Amber Brand) only. The app stays dark-only.
- forui inside the existing `MaterialApp`, with screen-by-screen migration and a global palette switch first.
- Inter bundled for UI. Lucide icons. Monospace fonts unchanged.
- A new terminal theme "YourSSH Amber" (the name "YourSSH Dark" is already taken by an existing catalog theme), default for new installs only.
- Custom `Ys*` components for tab bar, status bar, file table and host card.
- Seven phases, each PR shippable. Redesign before iOS.
- A shared `packages/yourssh_ui`, so the plugin packages are redesigned too (phase 5).
- Mockups are illustrative. No new measurement or data plumbing.
- Mobile keeps its structure and only gets restyled.
- The owner OKs each phase's screenshots before merge.
- No Flutter pin bump inside this project.
- The SDK bump to Dart ^3.13 that forui requires.

## Left to the builder

- Exact spacing and size choices within the token scale. Animation and hover details.
- Whether `Ys*` components wrap forui primitives or are drawn directly with tokens.
- How forui style deltas are organised in `YsTheme`.
- Per-screen layout refinements that keep the same information and actions.
