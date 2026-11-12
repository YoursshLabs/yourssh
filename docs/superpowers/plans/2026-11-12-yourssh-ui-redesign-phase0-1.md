# YourSSH UI redesign — Phase 0 (Foundation) and Phase 1 (Shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put forui and the "Amber Brand" design system under the whole app (Phase 0), then rebuild the app shell — sidebar, top tab bar, toasts, dialogs — on it (Phase 1).

**Architecture:**
- A new Flutter package, `packages/yourssh_ui`, owns the tokens (`YsColors`), the forui theme (`ysThemeData()`), the Material fallback theme (`ysMaterialTheme()`) and the shared `Ys*` components, and re-exports forui.
- The app wraps its `MaterialApp` content in `FTheme` + `FToaster`. It re-points `AppColors`/`MobileColors` at the tokens so every screen recolours at once, then replaces the shell widgets screen-piece by screen-piece.

**Tech Stack:** Flutter (CI pin 3.47.1), forui 0.27.x, provider, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-12-yourssh-ui-redesign-design.md` (reference mockups in `docs/superpowers/specs/assets/ui-redesign/`).

## Global Constraints

**Toolchain and dependencies**
- CI builds with Flutter **3.47.1**. forui 0.27.x needs Flutter ≥ 3.47.0 / Dart ≥ 3.13. Raise `environment.sdk` to `^3.13.0` in `app/` and `packages/yourssh_ui`.
  - If no forui 0.27.x resolves and builds on 3.47.1, use the newest forui release that does.
  - Never bump the Flutter pin. Stop and report instead.
- Run `flutter pub get` **without** `PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL`. `app/pubspec.lock` may change only by adding or updating forui and its transitive dependencies, and every `url:` in it stays `https://pub.dev`. Check with `grep -c flutter-io.cn app/pubspec.lock` → 0.

**Look and type**
- Tokens, copied verbatim from the spec:

  | Token | Value |
  |---|---|
  | background | `#0D0C0A` |
  | card | `#161412` |
  | secondary/muted | `#26231F` |
  | foreground | `#F5F5F4` |
  | mutedForeground | `#A8A29E` |
  | border | `#FFEBD2` at 12% (`0x1FFFEBD2`) |
  | primary | `#F3A231` |
  | primaryForeground | `#141416` |
  | accentText | `#FFC85A` |
  | chrome | `#080706` |
  | sidebar | `#110F0D` |
  | terminalSurface | `#0E0C0A` |
  | ok / warn / off / error | `#22C55E` / `#EAB308` / `#71717A` / `#EF4444` |

  Spacing 4/8/12/16/24/32. Radii: 6 controls, 10 cards, 14 mobile cards.
- The app stays dark-only (`ThemeMode.dark`).
- UI text uses the **bundled** Inter font, family name `Inter`. Do not use `google_fonts` for UI text.
- Icons in new or rebuilt widgets: `FLucideIcons` (forui).

**Behaviour**
- No new features. Navigation, actions, hotkeys, keys and semantics labels the existing tests or users rely on stay.
- Every icon-only button keeps or gets a tooltip and a semantics label.

**Process**
- Commit messages: Conventional Commits, with **no** `Co-Authored-By` and no `Claude-Session` trailer.
- Verify the app with `cd app && flutter analyze --no-fatal-infos` (0 errors) and `flutter test` (all green).

## Review Focus

1. A forui widget built where no `FTheme` ancestor exists: a dialog route pushed on the root navigator, an overlay, a toast fired from `main.dart` without a widget context, or a widget test that pumps a bare `MaterialApp`. Expect it to render, not throw "FTheme not found". This is pinned by tests in Task 3 (root wrapping), Task 9 (global toast) and Task 10 (dialog from root navigator).
2. Existing users' terminal theme silently changes to the new default. Expect an install with saved hosts to keep "Dracula" when it never chose a theme. Pinned in Task 5.
3. "Connected / online / success" indicators turn amber after the accent changes. Expect them to stay green. Pinned in Task 4: `AppColors.success` is used by status dots and success toasts.
4. Text on the new palette below WCAG AA. Pinned by the contrast test in Task 2.
5. Shell navigation regressions:
   - Command-palette nav commands and hotkeys still switch sections.
   - Plugin and script-panel nav items still appear.
   - Session tabs keep middle-click close, pinned-tab protection, reorder, rename and the context menu.

   Pinned in Task 7 and Task 8.

---

## Phase 0 — Foundation (PR 1)

### Task 1: `packages/yourssh_ui` scaffold with forui, wired into the app

**Files:**
- Create: `packages/yourssh_ui/pubspec.yaml`, `packages/yourssh_ui/lib/yourssh_ui.dart`, `packages/yourssh_ui/test/forui_smoke_test.dart`, `packages/yourssh_ui/analysis_options.yaml` (include `package:flutter_lints/flutter.yaml` like the other packages)
- Modify: `app/pubspec.yaml` (sdk `^3.13.0`; add `yourssh_ui: path: ../packages/yourssh_ui`), `app/pubspec.lock`
- Modify: `.github/workflows/pr-test.yml` — add `packages/yourssh_ui` tests (`flutter test`) to an existing Flutter package job or a new small `ui` job on `ubuntu-latest` with the same pinned actions and `${{ env.FLUTTER_VERSION }}`, and add it to the `test` aggregate `needs`/result check

**Interfaces:**
- Produces: `package:yourssh_ui/yourssh_ui.dart` exporting `package:forui/forui.dart` (so app code imports one library).

- [ ] **Step 1:** Write `forui_smoke_test.dart`. Pump `FTheme(data: FThemes.neutral.dark /* the name forui 0.27 uses */, child: FButton(onPress: () {}, child: Text('ok')))` inside a `MaterialApp`. Expect `find.text('ok')` to find one widget.
- [ ] **Step 2:** Run `cd packages/yourssh_ui && flutter test`. Expected: FAIL, because the package and forui don't exist yet.
- [ ] **Step 3:** Create the package:
  - `name: yourssh_ui`, `publish_to: none`, sdk `^3.13.0`.
  - Dependencies: `flutter`, `forui: ^0.27.7`. Dev dependencies: `flutter_test`, `flutter_lints`.
  - `lib/yourssh_ui.dart` exports forui.
  - Add the app path dependency and bump the app's sdk.
- [ ] **Step 4:** Run, in order:
  - `cd packages/yourssh_ui && flutter pub get && flutter test`. Expected: PASS.
  - `cd app && flutter pub get && flutter analyze --no-fatal-infos && flutter test`. Expected: 0 errors, all green.
  - `grep -c flutter-io.cn app/pubspec.lock`. Expected: `0`.
- [ ] **Step 5:** Commit `feat(ui): add yourssh_ui package with forui`.

*(The controller pushes the branch and runs CI after this task to prove forui on Flutter 3.47.1 before Task 2 starts.)*

### Task 2: Tokens and themes (`YsColors`, `ysThemeData()`, `ysMaterialTheme()`)

**Files:**
- Create: `packages/yourssh_ui/lib/src/ys_colors.dart`, `ys_metrics.dart`, `ys_theme.dart`; export them from `lib/yourssh_ui.dart`
- Test: `packages/yourssh_ui/test/ys_theme_test.dart`, `packages/yourssh_ui/test/contrast_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class YsColors` with `static const Color` fields: `background`, `card`, `secondary`, `muted`, `foreground`, `mutedForeground`, `border`, `primary`, `primaryForeground`, `accentText`, `chrome`, `sidebar`, `terminalSurface`, `ok`, `warn`, `off`, `error`. Values are the Global Constraints tokens.
  - `abstract final class YsSpace` with `s1=4, s2=8, s3=12, s4=16, s5=24, s6=32`.
  - `abstract final class YsRadius` with `control=6, card=10, mobileCard=14`.
  - `const String kYsFontFamily = 'Inter'`.
  - `FThemeData ysThemeData()`: forui's neutral dark theme with its colour set overridden by `YsColors` (background, foreground, primary, primaryForeground, secondary, secondaryForeground = foreground, muted, mutedForeground, border, card, destructive = error) and typography family `Inter`.
  - `ThemeData ysMaterialTheme()`:
    - Dark, Material 3, `fontFamily: 'Inter'`, scaffold background = background, `ColorScheme.dark` with primary = primary, onPrimary = primaryForeground, surface = background, error = error.
    - `dividerColor` = border.
    - Component themes matching the tokens, so not-yet-migrated Material widgets look native to the system:
      - `TooltipThemeData`: card background, 1 px border, radius 6, foreground text 12 px.
      - `PopupMenuThemeData`: card, radius 10, border.
      - `DialogThemeData`: card, radius 10.
      - `SnackBarThemeData`: card, floating.
      - `InputDecorationTheme`: filled secondary, radius 6, focused border primary.
      - `SwitchThemeData`: thumb foreground; track primary when selected.
      - `TextButtonThemeData`: foreground primary.
      - `ElevatedButtonThemeData`: primary background, primaryForeground text.
      - `OutlinedButtonThemeData`: border.

- [ ] **Step 1:** Write the tests.
  - `ys_theme_test.dart`:
    - `ysThemeData().colors.primary == YsColors.primary`.
    - `.colors.background == YsColors.background`.
    - `ysMaterialTheme().colorScheme.primary == YsColors.primary`.
    - `ysMaterialTheme().textTheme.bodyMedium!.fontFamily == 'Inter'`.
    - `ysMaterialTheme().brightness == Brightness.dark`.
  - `contrast_test.dart`: implement the WCAG relative-luminance contrast ratio in the test. Alpha-blend `border` onto background before measuring. Assert:
    - ≥ 4.5 for foreground on background, card, secondary and chrome.
    - ≥ 4.5 for mutedForeground on background and card.
    - ≥ 4.5 for primaryForeground on primary.
    - ≥ 4.5 for accentText on background.
    - ≥ 3.0 for primary on background (UI glyphs).
    - ≥ 3.0 for ok and error on card.
- [ ] **Step 2:** Run `flutter test` in packages/yourssh_ui. Expected: FAIL (symbols missing).
- [ ] **Step 3:** Implement. If a contrast pair fails, change only that token, by the smallest lightness step that passes. Record the old and new value in the commit body and the report.
- [ ] **Step 4:** Run `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(ui): Amber Brand tokens and forui/Material themes`.

### Task 3: Bundled Inter and the app root on `FTheme`

**Files:**
- Create: `app/assets/fonts/inter/Inter-Regular.ttf`, `Inter-Medium.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf`, `app/assets/fonts/inter/OFL.txt` (from the official rsms/inter v4 release zip — static TTFs)
- Create: `app/test/helpers/ys_test_app.dart`
- Modify: `app/pubspec.yaml` (fonts: family `Inter`, weights 400/500/600/700), `app/lib/main.dart` (MaterialApp `theme`/`darkTheme` = `ysMaterialTheme()`, `builder` wraps the child in `FTheme(data: ysThemeData(), child: FToaster(child: child!))`), `app/lib/theme/app_theme.dart` (`buildAppTheme()` returns `ysMaterialTheme()`), `app/lib/mobile/mobile_app.dart` (same root wrapping; `buildMobileTheme()` returns `ysMaterialTheme()`), `app/lib/mobile/theme/mobile_theme.dart` (`mobileHeading`/`mobileBody` use bundled `Inter` via plain `TextStyle(fontFamily: 'Inter', …)`; `mobileMono` uses `'Roboto Mono for Powerline'`, already bundled; drop the `google_fonts` import there)
- Test: `app/test/theme/ys_root_test.dart`

**Interfaces:**
- Produces: `Widget ysTestApp(Widget child)` in `app/test/helpers/ys_test_app.dart`. It is a `MaterialApp(theme: ysMaterialTheme(), builder: <same FTheme+FToaster wrapping as main>, home: Scaffold(body: child))`. Later tasks' widget tests use it.
- Produces: `Widget ysRootBuilder(BuildContext, Widget?)`, exported from `package:yourssh/theme/app_theme.dart`. Both `main.dart` and `mobile_app.dart` and the test helper use it as `MaterialApp.builder`, so the wrapping is one function.

- [ ] **Step 1:** Write `ys_root_test.dart`:
  - (a) An `FButton` inside `ysTestApp` renders.
  - (b) A route pushed with `showDialog` on the root navigator, whose content is an `FCard`, renders without exception. The builder wraps the Navigator, so dialog routes inherit `FTheme`.
  - (c) `Theme.of(ctx).textTheme.bodyMedium!.fontFamily == 'Inter'`.
  - (d) `mobileBody().fontFamily == 'Inter'` and `mobileMono().fontFamily == 'Roboto Mono for Powerline'`.
- [ ] **Step 2:** Run `cd app && flutter test test/theme/ys_root_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement as listed. Fetch the Inter TTFs from the official GitHub release with `curl` into the assets dir, and include OFL.txt.
- [ ] **Step 4:** Run the new test, then the full `flutter test` and `flutter analyze --no-fatal-infos`. Expected: green, 0 errors.
- [ ] **Step 5:** Commit `feat(ui): bundle Inter and wrap the app root in FTheme`.

### Task 4: Palette switch — `AppColors`/`MobileColors` onto the tokens, success stays green

**Files:**
- Modify: `app/lib/theme/app_theme.dart`. In `AppColors`:
  - `bg`=background, `sidebar`=sidebar, `card`=card, `cardHover`=secondary, `border`=border, `accent`=primary, `accentDim`=`Color(0xFFE87C08)`.
  - `textPrimary`=foreground, `textSecondary`=mutedForeground, `textTertiary`=`Color(0xFF78716C)`.
  - `red`=error.
  - New `success`=ok, `warning`=warn, `offline`=off.
  - `hostColors` and `tabColors` unchanged.
  - `AppSnack.success` uses `success`.
- Modify: `app/lib/mobile/theme/mobile_theme.dart` `MobileColors`:
  - `accent`=primary, `accentSoft`=`Color(0xFF2A2010)`.
  - `bg`=background, `surface`=card, `surfaceAlt`=chrome, `border`=border, `borderSoft`=`Color(0x14FFEBD2)`.
  - `textPrimary`=foreground, `textMuted`=mutedForeground, `textFaint`=`Color(0xFF78716C)`.
  - `green`=ok, `red`=error, `yellow`=warn.
  - `fieldFill`=secondary.
  - `blue` and `tabInactive` unchanged.
- Modify: every `AppColors.accent` / `accentDim` / `Colors.green` use under `app/lib` whose meaning is connected / online / success / "ok" / "added" → `AppColors.success`. Uses meaning primary action, selected or active stay `accent`.
- Test: `app/test/theme/app_theme_test.dart` (extend), `app/test/theme/status_colors_test.dart`

**Interfaces:**
- Consumes: `YsColors` (Task 2).
- Produces: `AppColors.success`, `AppColors.warning`, `AppColors.offline`. Later phases use these for status.

- [ ] **Step 1:** Write the tests:
  - `AppColors.bg == YsColors.background`, `AppColors.accent == YsColors.primary`, `AppColors.success == YsColors.ok`, `MobileColors.accent == YsColors.primary`.
  - In `status_colors_test.dart`, pump `SessionTab` for a connected session, using the existing `session_tab_test.dart` setup, and assert its health dot is `AppColors.success`. Find the dot by its existing key or semantics, or add `Key('session-health-dot')`.
  - Pump `AppSnack.success` in `ysTestApp` and assert the toast or snack background is `AppColors.success`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement the re-pointing.
  - Classify all 193 `AppColors.accent` and 5 `accentDim` uses (46 files) plus 19 `Colors.green` uses. List every changed site in the report as a table: file:line, old → new, reason.
  - Keep the 427 hard-coded `Color(0x…)` literals in widgets for their screen phases, except literals equal to the old accent green `0xFF22C55E` or `0xFF16A34A`. Map those by the same success-vs-accent rule.
- [ ] **Step 4:** Run the full `flutter test` and analyze. Expected: green. Fix tests that asserted the old colour values to assert the token instead.
- [ ] **Step 5:** Commit `feat(ui): switch the app palette to Amber Brand tokens`.

### Task 5: "YourSSH Amber" terminal theme, default for new installs only

**Files:**
- Modify: `app/lib/theme/terminal_themes.dart` (add `TerminalThemeEntry('YourSSH Amber', _yourSshAmber)` as the **first** catalog entry; "YourSSH Dark" stays unchanged as the second)
- Modify: `app/lib/providers/settings_provider.dart` (load: the default when the `terminalTheme` pref is absent)
- Test: `app/test/theme/terminal_themes_test.dart` (extend), `app/test/settings_provider_test.dart` (extend)

**Interfaces:**
- Produces: theme name constant `kDefaultTerminalTheme = 'YourSSH Amber'` in `terminal_themes.dart`.

- [ ] **Step 1:** Write the tests.
  - The theme's `background == YsColors.terminalSurface`, `cursor == YsColors.primary`, and `selection` is primary at alpha `0x55`.
  - `terminalThemeByName('nope')` still returns the first entry, which is now YourSSH Amber.
  - Settings, three cases:

    | Prefs at load | `terminalTheme` | Persisted |
    |---|---|---|
    | Empty (fresh install) | `'YourSSH Amber'` | yes |
    | `yourssh.hosts` present, no `terminalTheme` (existing install that never chose) | `'Dracula'` | yes |
    | `terminalTheme='Nord'` | `'Nord'` | — |

- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
  - ANSI colours: reuse "YourSSH Dark"'s desaturated ANSI set. Change only background, cursor, selection and the search-hit colours: hit background primary, current-hit background accentText, hit foreground terminalSurface. Foreground `#E7E5E4`.
  - On load, when `terminalTheme` is absent, decide once and persist immediately: `'Dracula'` if `yourssh.hosts` exists, else `kDefaultTerminalTheme`.
  - Change any other code that hard-codes `'Dracula'` as the default (grep for it) to read the setting.
- [ ] **Step 4:** Run the tests and the full suite. Expected: green.
- [ ] **Step 5:** Commit `feat(ui): YourSSH Amber terminal theme for new installs`.

### Task 6: Phase 0 docs

**Files:**
- Modify: `CLAUDE.md`:
  - Add a "Design system" paragraph: `packages/yourssh_ui`, tokens, `ysRootBuilder`, `ysTestApp`, Inter bundled, Lucide icons, and the rule that new UI uses forui or `Ys*`.
  - Update the "dark-only; theme constants live in `app/lib/theme/app_theme.dart`" sentence.
- Modify: `CHANGELOG.md` `[Unreleased]` → `### Changed`: the new look (palette, Inter, terminal theme for new installs).

- [ ] **Step 1:** Write from the code as merged in Tasks 1–5.
- [ ] **Step 2:** Commit `docs: describe the yourssh_ui design system`.

*(End of Phase 0. The controller:*
- *runs `integration_test/feature_screenshots_test.dart` and `mobile_screenshots_test.dart` on macOS;*
- *opens PR 1 into `develop` with the screenshots next to the mockups;*
- *sends the screenshots to the owner;*
- *merges after CI is green and the owner gives an OK.)*

---

## Phase 1 — Shell (PR 2)

### Task 7: Sidebar on `FSidebar`

**Files:**
- Create: `app/lib/screens/shell/app_sidebar.dart` (moved out of `main_screen.dart`: `_Sidebar`, `_NavItem`, `_PluginNavItem`, `_ScriptPanelNavItem` → public `AppSidebar` and private items)
- Modify: `app/lib/screens/main_screen.dart` (use `AppSidebar`; remove the moved classes), `packages/yourssh_ui/lib/src/ys_theme.dart` (sidebar style: `sidebar` background; the selected item gets a primary-tinted background `primary` @ 12%, primary icon and text — the one place this style delta lives)
- Test: `app/test/screens/app_sidebar_test.dart`

**Interfaces:**
- Produces: `class AppSidebar extends StatelessWidget`. Its constructor has the same parameters the old `_Sidebar` took: the selected `NavSection`, `onSelect`, plugin and script-panel callbacks, and the active ids, so `MainScreen` wiring is unchanged.
- Sidebar layout, top to bottom, using `FSidebar` groups:
  - Brand header: app icon and "YourSSH".
  - Group "Connections": Hosts, Port Forwarding, Known Hosts.
  - Group "Files & Transfer": SFTP.
  - Group "Tools": Recordings, Audit Log, then the Dart plugin items and JS script-panel items in their existing order.
  - Group "Security": Keychain.
  - Footer: Plugins, Settings, then the version line `YourSSH v<version> · <update state>` from `UpdateProvider`.
- Every `NavSection` and every plugin or script item that the old sidebar showed must still be shown, and must call the same callback. No item is added and none is removed.

- [ ] **Step 1:** Write `app_sidebar_test.dart`, wrapped in `ysTestApp` with fake providers:
  - (a) Every `NavSection` label is present once: Hosts, Keychain, Port Forwarding, SFTP, Known Hosts, Recordings, Audit Log, Settings, Plugins.
  - (b) Tapping "Known Hosts" calls `onSelect(NavSection.knownHosts)`.
  - (c) A registered plugin item and a script-panel item render, and their callbacks fire.
  - (d) The selected item's label colour is `YsColors.primary`.
  - (e) Focus traversal with Tab reaches the nav items in visual order.
- [ ] **Step 2:** Run it. Expected: FAIL (`AppSidebar` is missing).
- [ ] **Step 3:** Implement. Use `FLucideIcons`. Keep any existing `Key`s.
- [ ] **Step 4:** Run the test and the full suite (main-screen and command-palette tests included). Expected: green.
- [ ] **Step 5:** Commit `feat(ui): sidebar on FSidebar`.

### Task 8: Top tab bar — `YsTab` chrome and `SessionTabBar`

**Files:**
- Create: `packages/yourssh_ui/lib/src/ys_tab.dart` (`YsTab`, the visual chrome of one browser-style tab), `app/lib/screens/shell/session_tab_bar.dart` (moved from `main_screen.dart`: `_TopTabBar`, `_PinnedTab`, `_AddTabBtn` and their helpers → public `SessionTabBar`)
- Modify: `app/lib/widgets/session_tab.dart` (render through `YsTab`; keep all behaviour), `app/lib/screens/main_screen.dart`
- Test: `packages/yourssh_ui/test/ys_tab_test.dart`, `app/test/widgets/session_tab_test.dart` (must stay green; extend)

**Interfaces:**
- Produces: `YsTab({required Widget label, Widget? leading, List<Widget> trailing = const [], required bool active, VoidCallback? onTap, VoidCallback? onMiddleClick, VoidCallback? onClose, String? closeTooltip, Color? colorTag})`.
  - Active state: `card` background, a 2 px `primary` bottom indicator, foreground text.
  - Inactive state: `chrome` background, mutedForeground text, `secondary` on hover.
  - The close button shows on hover or when active, and is an `FButton.icon` ghost with a tooltip.
- Produces: `SessionTabBar`, taking the same inputs the old `_TopTabBar` took.
  - Keep: pinned Home/SFTP tabs, the `ReorderableListView` with `onReorderItem: provider.reorderSessionItem`, the add button and its menu, `NotificationBell`, and the AI-chat toggle if present.
  - Background: `chrome`.

- [ ] **Step 1:** Write the tests.
  - `ys_tab_test.dart`:
    - Active shows the indicator, found by `Key('ys-tab-indicator')`.
    - `onMiddleClick` fires on a tertiary tap.
    - The close button has a tooltip and fires `onClose`.
  - `session_tab_test.dart`: all existing cases still pass. Add a case asserting middle-click on a pinned tab does not close it.
- [ ] **Step 2:** Run them. Expected: the new cases FAIL.
- [ ] **Step 3:** Implement. Rename, context menu, recording and colour dots, the agent-forwarding key icon, the OS glyph and the health dot all stay in `SessionTab`, which passes them into `YsTab` as `leading`/`trailing`.
- [ ] **Step 4:** Run the full suite. Expected: green.
- [ ] **Step 5:** Commit `feat(ui): session tab bar on YsTab`.

### Task 9: Toasts on forui — `showYsToast` and the SnackBar sweep

**Files:**
- Create: `packages/yourssh_ui/lib/src/ys_toast.dart`
- Modify: `app/lib/theme/app_theme.dart` (`AppSnack.error/info/success` call `showYsToast`); every `app/lib/**` file that builds a `SnackBar(` directly (78 sites across about 21 files, including `app/lib/mobile/**`), converted to `AppSnack.*` or `showYsToast`; `app/lib/main.dart` (`scaffoldMessengerKey` users fire toasts through `showYsToast(navigatorKey.currentContext!, …)` behind a null check)
- Test: `packages/yourssh_ui/test/ys_toast_test.dart`, `app/test/theme/app_snack_test.dart`

**Interfaces:**
- Produces:
  - `enum YsToastKind { info, success, error }`.
  - `void showYsToast(BuildContext context, String message, {YsToastKind kind = YsToastKind.info, String? actionLabel, VoidCallback? onAction, Duration? duration})`.
    - Default durations: info 3 s, success 3 s, error 5 s.
    - Built on forui's toaster (`showFToast` or the 0.27 equivalent) with the matching style: error = error border and icon, success = ok, info = card.
- A SnackBar with an `action:` maps to `actionLabel`/`onAction`. A SnackBar with custom content, such as a progress row, maps to the closest toast. List each such site in the report.

- [ ] **Step 1:** Write the tests.
  - `ys_toast_test.dart`:
    - Each kind shows its message.
    - The action button fires `onAction`.
    - The toast disappears after its duration, using `tester.pump(duration)`.
  - `app_snack_test.dart`:
    - `AppSnack.error` shows a toast whose message is visible.
    - A toast fired through the global `navigatorKey` context, with no local widget context, renders.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement, then sweep.
  - `grep -rn 'SnackBar(' app/lib` must afterwards return only hits in comments.
  - `grep -rn 'showSnackBar\|ScaffoldMessenger' app/lib` must return no live uses. `scaffoldMessengerKey` may stay on `MaterialApp` only if a plugin API still needs it; say so in the report.
- [ ] **Step 4:** Run the full suite. Tests that looked for `SnackBar` widgets now look for the message text. Expected: green.
- [ ] **Step 5:** Commit `feat(ui): toasts on forui across the app`.

### Task 10: Dialogs on forui — `showYsDialog`, `YsConfirmDialog` and the AlertDialog sweep

**Files:**
- Create: `packages/yourssh_ui/lib/src/ys_dialog.dart`
- Modify: every `app/lib/**` `AlertDialog(` (34 sites) → `YsDialog`/`YsConfirmDialog`; the 9 custom `Dialog(` shells keep their content but use `YsDialogFrame`
- Test: `packages/yourssh_ui/test/ys_dialog_test.dart`, plus existing dialog tests (must stay green)

**Interfaces:**
- Produces:
  - `Future<T?> showYsDialog<T>(BuildContext context, {required WidgetBuilder builder, bool barrierDismissible = true})` — forui's dialog route, or `showDialog` with FDialog content and the token barrier colour (black @ 60%).
  - `YsDialog({required String title, Widget? body, required List<Widget> actions})`, built on `FDialog`.
  - `Future<bool> showYsConfirm(BuildContext context, {required String title, required String message, String confirmLabel = 'Confirm', String cancelLabel = 'Cancel', bool destructive = false})`.
    - Returns false on cancel or dismiss.
    - When destructive, the confirm button uses the destructive variant.
  - `YsDialogFrame({required Widget child, double maxWidth = 560})`: card background, radius 10, border, padding 24.

- [ ] **Step 1:** Write `ys_dialog_test.dart`:
  - `showYsConfirm` returns true on confirm, false on cancel, and false on barrier tap.
  - The destructive variant renders.
  - A dialog opened from a context deep in the tree, through the root navigator, renders inside `FTheme`.
  - Escape closes a dismissible dialog.
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement, then sweep.
  - Keep each dialog's title, text, buttons, return values and keyboard behaviour. Enter confirms where it did before.
  - Security-relevant dialogs keep their exact wording and default focus on the safe choice: host-key TOFU/changed key, RDP certificate trust, plugin consent, delete confirmations, sudo prompt.
  - `grep -rn 'AlertDialog(' app/lib` must return no live uses.
- [ ] **Step 4:** Run the full suite. Expected: green.
- [ ] **Step 5:** Commit `feat(ui): dialogs on forui across the app`.

### Task 11: Phase 1 docs

**Files:**
- Modify: `CLAUDE.md`:
  - The "Navigation" paragraph: `AppSidebar` and `SessionTabBar` now live in `app/lib/screens/shell/`, and `SessionTab` renders through `YsTab`.
  - The design-system paragraph: `showYsToast`, `showYsDialog`/`showYsConfirm`/`YsDialogFrame`, and that `AppSnack` delegates to them.
- Modify: `CHANGELOG.md` `[Unreleased]` → `### Changed`: the new sidebar, tab bar, toasts and dialogs.

- [ ] **Step 1:** Write from the code.
- [ ] **Step 2:** Commit `docs: shell, toasts and dialogs on the design system`.

*(End of Phase 1. The controller runs the screenshot tests and opens PR 2 after PR 1 is merged, rebasing onto `develop`. It sends the screenshots to the owner and merges after CI is green and the owner gives an OK.)*

## Out of scope for this plan

These are decided here and noted so no task drifts into them:
- Tooltips, popup menus and context menus in individual screens. They are styled through `ysMaterialTheme()` in Task 2 and converted to `FTooltip`/`FPopoverMenu` in the phase that owns each screen: terminal context menu in Phase 3, SFTP entry menu in Phase 4.
- Plugin packages' own widgets (Phase 5).
- Screen bodies (Phases 2–6).
