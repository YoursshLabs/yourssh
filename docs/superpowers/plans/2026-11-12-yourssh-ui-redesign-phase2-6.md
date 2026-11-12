# YourSSH UI redesign — Phases 2–6 and clean-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild every remaining screen on the forui "Amber Brand" design system:
- Phase 2: Hosts
- Phase 3: Terminal workspace
- Phase 4: SFTP
- Phase 5: other desktop screens and the plugin packages
- Phase 6: Mobile

Then remove the legacy styling paths.

**Architecture:** Each task migrates one screen group from hand-styled Material to forui widgets, plus the `Ys*` components in `packages/yourssh_ui`. Behaviour stays the same. Files over ~900 lines are split along their existing private classes while they are touched.

**Tech Stack:** Flutter 3.50.0, forui 0.27.7 (`packages/yourssh_ui`), provider, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-12-yourssh-ui-redesign-design.md`. The mockups are in `docs/superpowers/specs/assets/ui-redesign/`.

**Builds on:** `docs/superpowers/plans/2026-11-12-yourssh-ui-redesign-phase0-1.md`, which covers the tokens, the root `FTheme`, `AppSidebar`, `YsTab`/`SessionTabBar`, `showYsToast` and `YsDialog`/`showYsConfirm`/`YsDialogFrame`.

## Global Constraints

**Design system**
- Follow CLAUDE.md "Design system". New and rebuilt UI uses forui widgets or `Ys*` components. Use `FLucideIcons`, the `YsColors`/`YsSpace`/`YsRadius` tokens, and `kYsFontFamily` Inter.
- Colours: `AppColors.success` for status, amber `accent`/`primary` for primary, active and selected.
- Dark-only.
- `app` and `yourssh_ui` import `package:flutter/material.dart`, not `material_ui` (ruling P6).

**Behaviour parity (spec non-goals and anti-goals)**
- No new features. Keep every action, shortcut, tooltip, semantics label, `Key`, and keyboard and focus behaviour.
- Icon-only buttons need a tooltip.
- Mockups are illustrative. Build only what the app already knows (spec "Mockups vs. real data").
- Security dialogs keep their exact wording and keep default focus on the safe choice.

**Tests**
- Existing tests stay green with their assertions intact. Only finders change: from type to text, key or semantics.
- New `Ys*` components get unit tests.
- Untested screens get at least one smoke test that pumps the screen in `ysTestApp` and checks its main actions are present.

**Verification, every task**
- `cd app && flutter analyze --no-fatal-infos`: 0 errors.
- Full `flutter test` green, plus the test suite of every touched package.
- Revert `app/analysis_options.yaml` if Flutter rewrites it.
- Never commit `app/macos/**/swiftpm/Package.resolved`.

**Commits**
- Conventional Commits, no `Co-Authored-By` or `Claude-Session` trailer, never pushed by implementers.

**Performance (spec anti-goal)**
- Terminal throughput must stay within ±5% of v0.3.0. The controller runs `integration_test/terminal_perf_test.dart` after Task 6.

## Review Focus

1. **Hidden actions.** A rebuilt screen loses an action that was only reachable from a context menu, long-press, double-click or hover button. Each task's report must include an old-versus-new action checklist.
2. **Lost keyboard flow.** Focus traversal or a keyboard shortcut stops working after a widget swap, for example Enter in a host form, Tab order, or Escape in sheets and dialogs. Each task adds a focus/Enter test for its main form or list.
3. **Overflow.** The window is resized to 900×600 (the desktop minimum) or a long host label or path appears, and the layout overflows. Each task adds a test that pumps the screen at 900×600 with a 60-character label or path and asserts no overflow error.
4. **Plugin UI lost the theme.** A plugin package screen built outside `ysRootBuilder` (pushed route, dialog, sheet) renders without `FTheme`. Task 14 tests every plugin screen inside `ysTestApp`.
5. **Mobile touch targets.** A touch target drops below 44 px, or touch sizing is missing because `ysThemeDataTouch` isn't applied. Task 16 and Task 17 assert the minimum hit size on primary actions.

---

## Phase 2 — Hosts (PR 3)

### Task 1: Host components in `yourssh_ui`

**Files:**
- Create in `packages/yourssh_ui/lib/src/`:
  - `ys_host_card.dart`
  - `ys_os_tile.dart`
  - `ys_section_header.dart`
  - `ys_empty_state.dart`
  - `ys_badge.dart`: tag and status chips over `FBadge`
- Export them all from `yourssh_ui.dart`.
- Test: `packages/yourssh_ui/test/ys_host_components_test.dart`

**Interfaces (produces):**
- `YsHostCard`:

  ```dart
  YsHostCard({
    required Widget leading,
    required String title,
    required String subtitle,
    Widget? statusDot,
    List<Widget> badges = const [],
    List<Widget> tags = const [],
    String? meta,
    bool selected = false,
    VoidCallback? onTap,
    VoidCallback? onDoubleTap,
    void Function(Offset)? onSecondaryTap,
    VoidCallback? onLongPress,
    Widget? trailingAction,
  })
  ```

  - Card style per `B-1-hosts.png`: radius 10, `card` background, `border`.
  - Selected: `primary` 1px border.
  - Hover: `secondary`.
- `YsOsTile({required Widget glyph, required Color color, double size = 36})`
- `YsSectionHeader({required String title, String? trailing})`
- `YsEmptyState({required IconData icon, required String title, String? message, Widget? action})`
- `YsTag(String label)`
- `YsStatusBadge(String label, {YsStatus status})`

**Steps:**
- [ ] Write the tests.
  - Render each component and assert:
    - title and subtitle text
    - selected border colour `YsColors.primary`
    - tap, double-tap, secondary-tap and long-press callbacks fire
    - empty-state action renders
  - Add a 900×600 overflow test with a 60-character title.
- [ ] Run them and confirm they fail.
- [ ] Implement.
- [ ] Run them and confirm they pass.
- [ ] Commit: `feat(ui): host card, OS tile, section header, empty state and badges`.

### Task 2: Hosts dashboard

**Files:**
- Split `app/lib/widgets/hosts_dashboard.dart` (1685 lines) into `app/lib/widgets/hosts_dashboard/`:
  - `hosts_dashboard.dart`: the public widget and state
  - `top_bar.dart`: `_TopBar`, `_SortBtn`, `_ViewToggle`, `_SplitNewBtn`
  - `facet_chip_bar.dart`
  - `group_card.dart`
  - `host_grid.dart`
  - `host_list.dart`
  - `dashboard_dialogs.dart`: `_MoveToGroupDialog`, `_ExportDialog`
  - `empty_state.dart`
- Keep `package:yourssh/widgets/hosts_dashboard.dart` as an export shim.
- Rebuild on forui:
  - Search: `FTextField`.
  - Sort: `FSelect` or `FPopoverMenu`.
  - View toggle and split button: `FButton` / `FButton.icon` group.
  - Facet chips: `FBadge` selectable.
  - Groups: `YsSectionHeader` plus group cards on `FCard`.
  - Hosts: grid and list on `YsHostCard`.
  - Context menus: `FPopoverMenu`.
  - Dialogs: already `YsDialog` from Phase 1.
- `network_discovery_sheet.dart` and `new_group_panel.dart` move onto forui widgets too.
- Tests:
  - existing `facet_chip_bar`, `hosts_dashboard_menu`, `hosts_dashboard_view`
  - new: discovery sheet smoke, new group panel smoke, overflow at 900×600

**Notes:**
- The dashboard already knows the "open sessions per host" count (`SessionProvider`) and the "x of N hosts" figure. Show them as in `B-1-hosts.png`.
- Do not add latency or degraded states.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Split the file and migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): hosts dashboard on forui`.

### Task 3: Host editor (`HostDetailPanel`)

**Files:**
- Split `app/lib/widgets/host_detail_panel.dart` (1561 lines) into `app/lib/widgets/host_detail_panel/`, one file per section. Read the current section list in the file. The sections cover:
  - general
  - credentials
  - connection chain
  - options
  - RDP
  - VNC
  - session template
  - proxy
  - OSC52
  - recording
- Keep the old path as an export shim.
- Rebuild on forui:
  - SSH/RDP/VNC switch: `FTabs`.
  - Fields: `FTextField` and `FSelect`.
  - Options: `FSwitch` in `FTileGroup`.
  - Footer: Delete (destructive), Test, Save, all `FButton`.
- Restyle `host_chain_editor.dart` and `agent_status_line.dart` to match.

**Tests:**
- All 8 existing `host_detail_panel_*` tests, `host_chain_editor` and `agent_status_line` stay green.
- New:
  - Enter in the label field saves.
  - Tab order runs label → hostname → port → username.
  - Overflow at 900×600.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Split and migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): host editor on forui`.

### Task 4: Import panel and bulk actions

**Files to rebuild on forui:**
- `app/lib/widgets/import_panel.dart`
- `app/lib/widgets/bulk/bulk_action_bar.dart`
- `bulk_run_dialog.dart`
- `bulk_push_dialog.dart`
- `bulk_diff_view.dart`
- `bulk_host_status_list.dart`

**Tests:**
- The 5 existing bulk tests stay green.
- New: `bulk_push_dialog` smoke, import panel smoke.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): import panel and bulk actions on forui`.

*(End of Phase 2. The controller captures the hosts screens and opens PR 3.)*

---

## Phase 3 — Terminal workspace (PR 4)

### Task 5: Workspace chrome and side panels

**Files:**
- `terminal_view.dart` frame: header chips for host, tmux and cwd, only where that data exists.
- `split_terminal_view.dart`: dividers styled with the tokens. Use `FResizable` only if it keeps the existing split behaviour exactly; otherwise keep the custom divider.
- Side panel:
  - `workspace_side_panel.dart`
  - `terminal_snippets_panel.dart`, on `FTileGroup`/`FTile` per `B-2-terminal.png`
  - `terminal_config_panel.dart`
  - `terminal_appearance_controls.dart`, using `FSelect` and the forui slider
  - `theme_picker.dart`
- Do **not** touch `TerminalView`/xterm rendering.

**Tests:**
- Existing: `terminal_snippets_panel`, `terminal_config_panel`, `terminal_appearance_controls`, `theme_picker`, `terminal_view_text_input`.
- New: `workspace_side_panel` smoke, `split_terminal_view` smoke.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): terminal workspace chrome and side panels on forui`.

### Task 6: Terminal bars, overlays and the status bar

**Files:**
- Create `packages/yourssh_ui/lib/src/ys_status_bar.dart`: `YsStatusBar({required List<Widget> leading, List<Widget> trailing = const []})`. Background `chrome`, 22 px, 11 px mono-ish text.
- Add an app adapter `app/lib/widgets/terminal_status_bar.dart` showing per-session data. Spec "Mockups vs. real data" fixes the contents:
  - SSH: status, `user@host`, "via" chain, agent-forwarding state, TERM, cols×rows, REC + elapsed.
  - Local PTY: shell + cols×rows.
  - RDP/VNC: resolution + status.
- Rebuild on forui:
  - `terminal_input_bar.dart`
  - `broadcast_toolbar.dart`
  - `suggestion_popup.dart`
  - `command_gutter.dart`
  - `record_button.dart`
  - `terminal_context_menu.dart`, on `FPopoverMenu`. Keep every item, including Reset Terminal.
  - `session_connecting_view.dart`
  - `network_stats_overlay.dart`
  - `server_monitor_sheet.dart`
  - `share_session_dialog.dart`
  - `join_share_dialog.dart`
  - `local_terminal_pane.dart`

**Tests:**
- Existing tests for each file stay green.
- New:
  - `YsStatusBar` unit test.
  - Status-bar adapter test for the three session types, asserting the exact fields listed above.
  - Share and join dialog smoke tests.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): terminal bars, overlays and status bar on forui`.

*(End of Phase 3. The controller runs `terminal_perf_test` and compares it with v0.3.0, ±5%. Then it captures screens and opens PR 4.)*

---

## Phase 4 — SFTP (PR 5)

### Task 7: `YsFileTable` and the two file panels

**Files:**
- Create `packages/yourssh_ui/lib/src/ys_file_table.dart`. It is generic over a row type:

  ```dart
  YsFileTable<T>({
    required List<T> rows,
    required List<YsColumn<T>> columns,
    Set<T> selected,
    void Function(T, {bool additive, bool range})? onSelect,
    void Function(T)? onOpen,
    void Function(T, Offset)? onContextMenu,
    YsSort? sort,
    void Function(YsSort)? onSort,
  })
  ```

  - Keyboard: up/down, Enter opens, Space toggles, Cmd/Ctrl+A.
  - Rows: 28 px.
- Migrate onto it:
  - `sftp_panel.dart`
  - `local_file_panel.dart`
  - `dual_panel_sftp_screen.dart`, with `FResizable` and `path_breadcrumb.dart` on `FBreadcrumb`
  - `entry_context_menu.dart`, on `FPopoverMenu`
  - `sftp_screen.dart`
- Keep drag-and-drop between panels, multi-select, history navigation, the elevated badge and checkboxes.

**Tests:**
- Existing: `sftp_panel_*`, `local_file_panel_checkbox`, `dual_panel_*`, `entry_context_menu`, `path_breadcrumb`.
- New:
  - `YsFileTable`: keyboard and selection.
  - Overflow at 900×600 with a 60-character path.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): SFTP panels on YsFileTable`.

### Task 8: Transfers, file dialogs and the editor chrome

**Files to rebuild on forui:**
- `sftp_transfer_panel.dart`, with `FDeterminateProgress`
- `permissions_dialog.dart`
- `sudo_password_dialog.dart`: security wording and focus unchanged
- `source_picker_dialog.dart`
- `code_editor_screen.dart` chrome
- In `assets/monaco_editor.html`, add a Monaco theme `yourssh-amber` built from the tokens: background terminalSurface, selection primary@0x55, cursor primary, gutter card. Make it the editor default.

**Tests:**
- Existing tests stay green.
- New: `code_editor_screen` chrome smoke.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): transfers, file dialogs and editor chrome on forui`.

*(End of Phase 4. The controller captures screens and opens PR 5.)*

---

## Phase 5 — Other desktop screens and plugins (PR 6)

### Task 9: Settings

**Files:**
- Split `settings_screen.dart` (1514 lines) into `app/lib/widgets/settings/`, one file per section:
  - Appearance
  - Terminal
  - Security
  - Sync
  - AI providers
  - Recording
  - Updates
  - Hotkeys (`hotkey_settings_screen.dart`)
  - Keyword highlights (`keyword_highlight_settings.dart`)
- Rebuild on `FTileGroup`, `FTile`, `FSwitch`, `FSelect` and `FTextField`, per `B-4-settings.png`.

**Tests:** new smoke test per section, covering presence and one toggle each, plus the existing settings provider tests.

**Steps:**
- [ ] Write the new tests.
- [ ] Confirm they fail.
- [ ] Split and migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): settings on forui`.

### Task 10: Management screens

**Files to rebuild on forui:**
- `port_forwarding_screen.dart`
- `known_hosts_screen.dart`
- `recording_library_screen.dart`
- `recording_player_widget.dart`
- `audit_screen.dart`

**Tests:** existing tests, plus smoke tests for `known_hosts`, the recordings library and the player.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): port forwarding, known hosts, recordings and audit on forui`.

### Task 11: Keys, sync, notifications and shell leftovers

**Files to rebuild on forui:**
- `keychain_screen.dart`
- `deploy_key_dialog.dart`
- `qr_export_dialog.dart`
- `qr_import_dialog.dart`
- `notification_bell.dart`
- `update_banner.dart`
- `command_palette.dart`
- `confirm_dialog.dart`: make it a thin wrapper over `showYsConfirm`
- `main_screen.dart` leftovers: `_RdpPasswordDialog`, `_AiChatToggle`, TOFU prompts
- `plugin_manager_screen.dart`
- `plugin_console_screen.dart`
- `plugin_consent_dialog.dart`: wording and focus unchanged
- `script_plugin_panel_screen.dart`
- `ai_chat_sidebar.dart`
- `tool_result_view.dart`
- Delete `plugin_marketplace_screen.dart`. It is unreferenced.

**Tests:** existing tests, plus smoke tests for:
- `deploy_key_dialog`
- `qr_export_dialog`
- `ai_chat_sidebar`
- `tool_result_view`
- `plugin_manager_screen`

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): keys, sync, notifications, palette and plugin screens on forui`.

### Task 12: Remote-desktop chrome and the in-app devops screens

**Files to rebuild on forui:**
- `rdp_workspace.dart` and `vnc_workspace.dart`: toolbar and overlays only. Keep the fullscreen pill behaviour.
- `containers_screen.dart`
- `kubernetes_panel.dart`
- `docker_panel.dart`
- `compose_panel.dart`
- `devops_tools_screen.dart`
- `mcp_server_screen.dart`
- `mail_catcher_screen.dart`
- `cloudflare_tunnel_screen.dart`
- `web_tools/port_forward_browser.dart`

**Tests:** existing tests, plus smoke tests for containers, kubernetes, mcp, mail catcher and cloudflare.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): remote-desktop chrome and devops screens on forui`.

### Task 13: Plugin packages

**Files:**
- Add `yourssh_ui: path: ../yourssh_ui` to `packages/yourssh_snippets`, `packages/yourssh_devops` and `packages/yourssh_web_tools`.
- Replace each package `theme.dart` with token aliases.
- Rebuild on forui:
  - `snippets_screen.dart`
  - `s3_browser_screen.dart`
  - `lan_share_screen.dart`
  - `devops_hub_screen.dart`
  - `http_client.dart`: split it (1522 lines)
  - `utility_tools.dart`
  - `embedded_browser.dart`
  - `web_tools_screen.dart`
- Plugin screens may be pushed as routes. Wrap each plugin root that `buildUI` returns so that it works inside `ysRootBuilder`, and test it in `ysTestApp`.

**Tests:** the existing package tests, plus a smoke test for each plugin screen in `ysTestApp`. The devops package needs a new `test/` directory and a `pr-test.yml` step.

**Steps:**
- [ ] Write the new tests.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): plugin packages on the design system`.

*(End of Phase 5. The controller captures screens and opens PR 6.)*

---

## Phase 6 — Mobile (PR 7)

### Task 14: Mobile foundations and shared widgets

**Files:**
- `app/lib/mobile/theme/mobile_tokens.dart`: spacing and radii become aliases of `YsSpace`/`YsRadius` where the values match. Keep mobile-only sizes.
- Rebuild on forui, using touch sizing:
  - `widgets/host_card.dart`, on `YsHostCard`
  - `host_avatar.dart`
  - `key_card.dart`
  - `snippet_card.dart`
  - `forward_rule_row.dart`
  - `list_group.dart`
  - `mobile_card.dart`
  - `section_header.dart`
  - `settings_row.dart`
  - `status_dot.dart`
  - `tag_chip.dart`
  - `latency_badge.dart`
  - `mobile_fab.dart`
  - `mobile_tab_bar.dart`, on `FBottomNavigationBar` with the same tab set

**Tests:**
- The existing mobile widget tests.
- New: key_card, snippet_card and forward_rule_row smoke tests.
- Minimum 44 px hit size on the FAB and on the tab items.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): mobile foundations on forui`.

### Task 15: Mobile screens

**Files to rebuild on forui:**
- `mobile_hosts_screen.dart`
- `mobile_add_host_screen.dart`
- `mobile_keys_screen.dart`
- `mobile_port_forward_screen.dart`
- `mobile_settings_screen.dart`
- `mobile_sync_screen.dart`
- `mobile_snippets_screen.dart`
- `mobile_sftp_screen.dart`
- `mobile_qr_scan_screen.dart`

Use `FHeader` for the headers, and remember it adds its own safe area.

**Tests:**
- Existing mobile screen tests.
- New: QR scan screen smoke test.
- Minimum 44 px hit size on primary actions.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): mobile screens on forui`.

### Task 16: Mobile terminal and security gates

**Files to rebuild on forui:**
- `mobile_terminal_screen.dart`: session chips and header per `B-5-mobile.png`
- `terminal/accessory_key_bar.dart`: `FButton` small keys, minimum 44 px
- `terminal/terminal_side_panel.dart`
- `security/app_lock_gate.dart`
- `security/tofu_watcher.dart`: wording and focus unchanged

**Tests:** existing tests, plus the 44 px hit size on accessory keys.

**Steps:**
- [ ] Write the new tests and adapt finders.
- [ ] Confirm they fail.
- [ ] Migrate.
- [ ] Confirm all tests pass.
- [ ] Commit: `feat(ui): mobile terminal and security gates on forui`.

*(End of Phase 6. The controller runs `integration_test/mobile_screenshots_test.dart` and opens PR 7.)*

---

## Clean-up (PR 8)

### Task 17: Remove legacy styling paths and add the lint gate

**Files:**
- Replace remaining direct `Color(0x…)` literals in app/lib widgets with tokens. Exempt the terminal theme catalog, `hostColors`/`tabColors` user palettes and OS glyph colours.
- Keep `AppColors` and `MobileColors` as `@Deprecated` aliases of `YsColors`. Do not delete them, because about 460 call sites would churn for no visual change. Record this as a deviation from the spec's "delete at the end".
- Add `tool/check_ui_lint.sh`, run by a pr-test step. It fails on new uses of any of these outside `packages/yourssh_ui/`:
  - `IconButton(`
  - `AlertDialog(`
  - `SnackBar(`
  - `Icons\.`
  - `ScaffoldMessenger`

  It scans `app/lib/` and `packages/yourssh_{snippets,devops,web_tools}/lib/`. An allowlist file holds the justified remaining sites, each with a reason.
- CLAUDE.md "Design system": update for the final state.
- CHANGELOG: the redesign entry.
- README: refresh the screenshots. The controller supplies them from the user-journey run.

**Tests:** the lint script runs in CI and passes, and its allowlist is reviewed.

**Steps:**
- [ ] Write the lint script and run it to see the current violations.
- [ ] Fix the violations or allowlist them with reasons.
- [ ] Commit: `chore(ui): token sweep, deprecate legacy colour aliases and add the UI lint gate`.
