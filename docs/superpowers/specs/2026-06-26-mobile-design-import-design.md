# Mobile UI Redesign — Claude Design import (Android)

**Date:** 2026-06-26
**Branch:** `feat/android-mobile-app`
**Status:** Approved design
**Design source:** `SSH Client.dc.html` — Claude Design project
`e783a344-8697-4d01-abb1-7cbed4764321` (imported via DesignSync). Row 1 = the
canonical v1 flow (9 screens). Rows 2–3 are exploratory variants and are **not**
part of this spec.

## Problem

The current mobile build (`app/lib/mobile/`, ~23 files / ~2,564 LOC, shipped by
the 2026-06-25 Termius-style pass) has a working 4-tab shell — **Hosts ·
Sessions · SFTP · Settings** — that reuses every desktop provider/service. A new,
more complete visual design has since been produced (a dark, Apple-inspired
amber-accent client covering nine screens). It differs from what ships today in
information architecture, accent color, and screen coverage:

- **IA:** new bottom tabs are **Hosts · Snippets · Keys · Settings**. Terminal and
  Files move out of the tab bar and become contextual (reached from a host /
  session). Snippets and Keys become first-class tabs (no mobile UI today).
- **Accent:** amber `#f7a01a` (today the app uses green `#22C55E`, shared with
  desktop via `AppColors`).
- **New screens:** dedicated **Keys**, **Snippets**, **Port forwarding**, and
  **Sync / QR pairing** screens (port forwarding has no mobile UI and its service
  is not wired into the mobile bootstrap).

Goal: replace the existing mobile UI with this design — matching its look and IA —
while reusing all connection/provider logic and losing none of the current
mobile feature set (biometric lock, TOFU, P2P import, terminal gestures).

## Reference design language

- Pure black screen background `#000`; surfaces `#161618` / `#0c0c0e`; borders
  `#232325` / `#1a1a1c`.
- **Accent amber `#f7a01a`** (selected tab, FAB, primary buttons, active toggles,
  focused field, cursor).
- Status: green `#22c55e` (online / success), red `#ff6464` (error / warn),
  blue `#4da3ff` (paths / folders), yellow `#ffce35` (log warn).
- Fonts: **Manrope** (large headings), **Inter** (UI body), **Roboto Mono**
  (hostnames, IPs, terminal, commands, fingerprints).
- iOS-style grouped lists: rounded `14–15px` cards, uppercase section labels
  (`11px`, letter-spacing `1px`, `#5d5d63`), hairline row dividers.
- Pill chips (`980px` radius) for filters/folders; `56px` rounded-square FAB;
  `78px` blurred bottom tab bar.

## Non-goals (YAGNI)

- No change to desktop: `app_theme.dart` (`buildAppTheme`, `AppColors`),
  `MainScreen`, and the desktop bootstrap are untouched. Desktop stays green.
- No change to `providers/*`, `services/*`, `models/*`, the `main.dart`
  `isMobilePlatform` gate, or `runtime_platform.dart` (additive wiring only in the
  mobile bootstrap).
- No new SSH/terminal engine — reuse `xterm` + existing accessory bar / side panel
  / gestures, reskinned.
- No RDP / VNC / local-shell / plugins / recording / audit UI on mobile.
- No tablet/foldable multi-pane layout (phone only).
- Rows 2–3 of the design (Terminal / Hosts variants) are out of scope.

## Approach

**Rewrite in place + a mobile theme layer.** Keep the `app/lib/mobile/` root,
bootstrap pattern, providers, security (app-lock / TOFU), and terminal engine.
Add a mobile-only amber theme, expand the token/primitive layer, rebuild the four
tab screens, and add the new contextual + tab screens. Rejected:

- *Parallel `mobile_v2/`*: duplicates bootstrap + code, two UIs to maintain — not
  justified.
- *Reskin only* (colors/spacing, keep old IA): cannot deliver the new IA, Keys /
  Snippets / Port-forwarding screens — fails the brief.

## Architecture

```
app/lib/mobile/
├── theme/
│   ├── mobile_tokens.dart           # EXPAND — + section-label, badge, divider tokens
│   └── mobile_theme.dart            # NEW — MobileColors (amber) + buildMobileTheme()
├── mobile_app.dart                  # EDIT — apply buildMobileTheme()
├── mobile_bootstrap.dart            # EDIT — wire PortForwardService/Provider,
│                                    #        SnippetProvider, KeyGenService
├── nav/
│   └── mobile_home_shell.dart       # REWRITE — tabs: Hosts/Snippets/Keys/Settings
├── screens/
│   ├── mobile_hosts_screen.dart     # REWRITE — search + folder chips + grouped cards + FAB
│   ├── mobile_add_host_screen.dart  # REWRITE — grouped GENERAL/AUTH/ADVANCED form
│   ├── mobile_terminal_screen.dart  # NEW (from mobile_sessions_screen) — pushed route
│   ├── mobile_sftp_screen.dart      # REWRITE — breadcrumb + sort + typed list (contextual)
│   ├── mobile_keys_screen.dart      # NEW — key list + Generate/Import
│   ├── mobile_snippets_screen.dart  # NEW — category chips + command cards (tap-to-run)
│   ├── mobile_port_forward_screen.dart # NEW — rule list + start/stop + add (contextual)
│   ├── mobile_settings_screen.dart  # REWRITE — sync banner + grouped sections
│   ├── mobile_sync_screen.dart      # NEW — Supabase status + QR pairing
│   └── mobile_qr_scan_screen.dart   # KEEP — camera scanner (reskin header only)
├── terminal/                        # KEEP + reskin: accessory_key_bar,
│                                    #   accessory_bar_controller, terminal_side_panel,
│                                    #   terminal_cursor_gestures
├── security/                        # KEEP unchanged: app_lock_gate, tofu_watcher
├── widgets/                         # REWRITE to design: host_card, host_avatar,
│                                    #   mobile_card, status_dot, tag_chip, section_header
│                                    # NEW: latency_badge, list_group, settings_row,
│                                    #   mobile_tab_bar, mobile_fab
├── services/
│   └── host_reachability_probe.dart # NEW — best-effort TCP-connect latency probe
└── sync/transfer_code.dart          # KEEP
```

- **Theme isolation:** `buildMobileTheme()` clones the shared dark theme and
  overrides `colorScheme.primary`/accent with `MobileColors.accent` amber; applied
  only in `mobile_app.dart`. Desktop never sees it.
- **Fonts:** via `google_fonts` (`Manrope`, `Inter`, `Roboto Mono`) — cached after
  first load; centralized in `mobile_theme.dart` text-theme builders so screens
  reference theme text styles, not raw font names.

## Navigation & session model

- **Bottom tabs** (`MobileHomeShell`): Hosts · Snippets · Keys · Settings.
- **Terminal = pushed route** backed by `SessionProvider` (not a tab):
  - Tapping a host (online, or to connect) pushes the Terminal focused on that
    host's session. A session-tabs strip switches between all live sessions; **+**
    opens a host picker to add another.
  - Backing out of Terminal does **not** kill sessions (they remain in
    `SessionProvider`); a connected host card re-opens Terminal on re-tap. Closing
    the last session pops back to Hosts.
  - Terminal header `⋮`/icons open **Files (SFTP)** and **Port forwarding** for the
    current host (pushed routes).
- **FAB** on Hosts → New host (push). **Settings → Pair new device** →
  Sync/QR (push). **QR scan** pushed from Sync.
- Folder chips on Hosts and the "Group" field on New host map to the existing
  **host tags** system; grouped list sections are derived from tags.

## Screens — data sources & key components

1. **Hosts** — search field, horizontal folder chips (tags), tag-grouped sections,
   host card (seeded avatar tile, nickname, `user@ip` mono, latency/offline badge),
   FAB +. ← `HostProvider`, `HostReachabilityProbe`, `SessionProvider`.
2. **New host** — grouped form: GENERAL (nickname/host/port) · AUTHENTICATION
   (username / method / key + biometric-unlock toggle) · ADVANCED (group=tag,
   run-on-connect=`startupSnippet`). "Save & connect". Preserves
   RDP/VNC/jump-chain/cert/agent fields on edit. ← `HostProvider`, `KeyProvider`.
3. **Terminal** — session-tabs strip + `xterm` `TerminalView` + reskinned shortcut
   bar + soft keyboard; reuse accessory bar, side panel, cursor-drag, pinch-zoom.
   ← `SessionProvider`, `SshService`.
4. **Files (SFTP)** — breadcrumb + sort + typed file/folder list with sizes;
   upload/download. ← `SftpTransferService` (upgrade `mobile_sftp_screen`).
5. **Keys** — key list (type · #hosts in use · SHA256 fingerprint mono) +
   Generate / Import. ← `KeyProvider`, `KeyGenService`.
6. **Snippets** — category filter chips + command cards (mono), tap-to-run into the
   active session. ← `SnippetProvider`, `SessionProvider.sendInput`.
7. **Port forwarding** — LOCAL/REMOTE/DYNAMIC rule rows with active/stopped state,
   start/stop toggle, "Add rule". ← `PortForwardProvider` + `PortForwardService`
   (newly wired in mobile bootstrap, auto-start after `ready`).
8. **Settings** — sync banner + grouped sections: TERMINAL (font/size/theme via
   shared `TerminalAppearanceControls`) · SECURITY (biometric = app-lock, auto-lock)
   · KEYBOARD & SYNC (shortcut bar toggle, Supabase sync, pair device) + version.
   ← `SettingsProvider`, `SyncProvider`, app-lock state.
9. **Sync / QR** — Supabase E2E status + QR pairing render + Scan QR.
   ← `SyncService`, `P2PSyncService`, `mobile_qr_scan_screen`.

## Cross-cutting

- **Latency badge:** `HostReachabilityProbe` does a best-effort TCP `Socket.connect`
  with a short timeout per visible host (debounced / refreshed on pull), reporting
  round-trip ms or offline; never blocks the UI and never throws. "N online · M
  total" is derived from probe results. Failure → treated as offline.
- **Preserved features:** biometric app-lock (`app_lock_gate`), TOFU host-key dialog
  (`tofu_watcher`), P2P QR import, pinch-zoom, long-press cursor-drag — all retained.
- **No feature regressions** versus the current mobile build.

## Error handling

- Probe / SFTP / port-forward failures surface inline (badge, snackbar, row state)
  and never crash the screen; providers already fail-soft.
- Connect failures route through existing `SessionProvider` error states shown in
  the Terminal tab.

## Testing

- Widget tests for primitives: host card, list group, settings row, tag/category
  chip, status dot, latency badge, tab bar.
- Screen smoke tests (Hosts, Snippets, Keys, Settings, New host, Port forwarding)
  with fake/stub providers, following existing mobile test patterns.
- `HostReachabilityProbe` unit-tested with an injected connector (no real sockets).
- `flutter analyze` clean; `flutter test` green.

## Phasing (drives the implementation plan)

- **P1 Foundation** — `mobile_theme` (amber) + expanded tokens + google_fonts +
  rebuilt primitives + 4-tab `MobileHomeShell` shell.
- **P2 Tab screens** — Hosts (+ reachability probe) · Snippets · Keys · Settings +
  New host.
- **P3 Session flow** — Terminal reskin + pushed-route session model + Files.
- **P4 Power features** — Port forwarding (wire `PortForwardService`) + Sync/QR.
- **P5 Polish** — tests, `flutter analyze`, design-fidelity pass.

## Open decisions (resolved)

- Latency: **TCP-connect probe** (best-effort ms badge), consistent with the
  "full functionality" scope.
- Fonts: **`google_fonts`** (network-on-first-use, then cached).
