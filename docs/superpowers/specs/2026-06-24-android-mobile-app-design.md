# Android Mobile App (v1) — Design Spec

**Date:** 2026-06-24
**Status:** Approved (architecture); ready to plan

## Overview

Add **Android** as a target of the existing `app/` Flutter project, shipping a
focused **mobile SSH client** (v1). The app reuses the existing
platform-agnostic core (models, providers, SSH/SFTP/sync/storage services) and
adds a new mobile UI layer plus a small set of platform abstractions so the
four desktop-only concerns (window control, global hotkeys, desktop
notifications, local PTY) no longer leak into the Android build. iOS is
explicitly deferred but the structure must not preclude it.

Direction: a **companion mobile SSH client** — pull hosts from the desktop via
sync, connect, work in the terminal, browse files. Not a full port.

## Scope

**In scope (v1):**
- New `android/` target (`flutter create --platforms=android .`)
- Multi-session SSH terminal (xterm fork) with a mobile **accessory key bar**
- Host management (CRUD, groups, tags, search) — reuses `HostProvider`
- Key management + 3 of the 4 auth methods that make sense on mobile: password,
  private key, certificate. **SSH agent auth is desktop-only** (no
  `SSH_AUTH_SOCK` / Windows pipe on Android) — hidden on mobile, not removed
  from the model.
- Known-hosts TOFU — reuses `KnownHostsProvider` + trust dialog
- Secure storage on **Android Keystore** (`flutter_secure_storage` already
  supports it)
- **Sync (import hosts from desktop):** Cloud Supabase sync + P2P QR sync
  (`mobile_scanner` already a dependency)
- **SFTP browser** — single-panel mobile layout (remote only); browse, upload
  (SAF picker), download (SAF save), open/view, rename, delete, permissions
- **Snippets + command history** — insert into the active session
- **Biometric app-lock** (`local_auth`) — gate app open + resume from
  background; mobile-only re-introduction of `local_auth`
- Terminal appearance settings (44 themes, font, size) — reuses
  `resolveTerminalAppearance` / `TerminalAppearanceControls`

**Out of scope (v1):**
- RDP / VNC (Rust FFI `.so` cross-compile via Android NDK) — large, deferred
- Port forwarding (Android background limits make this its own design)
- Local shell / PTY tabs (`flutter_pty`) — no local shell on mobile
- DevOps / WebTools / Script-engine plugins, MCP gateway, Cloudflare tunnel,
  mail catcher, S3, server monitor, network discovery
- Monaco code editor (`webview_flutter` works on Android, but defer)
- Split view, broadcast, global hotkeys, session recording, audit-log UI,
  AI chat sidebar
- iOS target

## Architecture

### Codebase layering (single `app/`, runtime branch)

Most of the existing tree is platform-agnostic and reused **as-is**. We
introduce a clear split between shared code, the existing desktop UI, and the
new mobile UI, and branch at the app root by platform.

```
app/lib/
  main.dart                 # branch: Platform.isAndroid ? MobileApp : DesktopApp
  models/                   # shared, unchanged
  providers/                # shared, unchanged (ChangeNotifier)
  services/                 # shared, unchanged where platform-agnostic
  platform/                 # NEW — abstractions for desktop-only concerns
    window_chrome.dart        # interface + desktop (window_manager) + mobile (no-op)
    global_hotkeys.dart       # interface + desktop (hotkey_manager) + mobile (no-op)
    app_notifier.dart         # interface + desktop (local_notifier) + mobile (flutter_local_notifications | no-op)
    local_shell_gate.dart     # local PTY only constructed on desktop
  desktop/                  # existing screens/ + widgets/ moved here (or kept as-is initially)
  mobile/                   # NEW — mobile screens + widgets
    mobile_app.dart           # MaterialApp + bottom-nav shell + MultiProvider reuse
    screens/                  # hosts, sessions, sftp, settings
    widgets/                  # terminal accessory bar, mobile session view, sftp list, ...
  theme/                    # shared (dark-only AppColors)
```

`main.dart` builds the same `MultiProvider` (shared providers) and the same
service instances, then mounts `MobileApp` on Android and the existing
`MainScreen` host on desktop. Service wiring callbacks (key lookup, host-key
verifier, sync-on-mutation) are shared; only the desktop-only abstractions get
a mobile implementation.

**Why runtime branch, not a second entrypoint:** keeps one `MultiProvider`
graph and one set of provider wiring, avoids duplicating `main.dart`'s
callback plumbing.

### Desktop-only dependency isolation

The four desktop-only plugins are addressed as follows:

| Concern | Plugin | Build impact on Android | Mobile handling |
|---|---|---|---|
| Window control | `window_manager` | Declares desktop platforms only → Android build skips its native; safe | `WindowChrome.noop` |
| Global hotkeys | `hotkey_manager` | Desktop-only → skipped | `GlobalHotkeys.noop` (in-app shortcuts only) |
| Desktop notifications | `local_notifier` | Desktop-only → skipped | `AppNotifier` via `flutter_local_notifications` (or no-op for v1) |
| Local PTY | `flutter_pty` (fork) | Fork **declares android/ios** (ffiPlugin) → builds fine; just never invoked on mobile | `LocalShell` not constructed on Android |

All direct calls to these plugins currently in `main.dart`/widgets get routed
through the `platform/` abstractions so the mobile tree never imports the
desktop plugin directly. **Spike 1 (below) must confirm the Android Gradle
build succeeds** with these dependencies present.

## Mobile UI

### Navigation

Bottom navigation with four destinations:

- **Hosts** — searchable list (compact rows), group/tag chips, FAB to add a
  host, host detail editor (mobile form), tap-to-connect.
- **Sessions** — the live terminals; a horizontally scrollable session tab
  strip + the active `TerminalView`.
- **SFTP** — single remote panel (pick a connected host), breadcrumb, list,
  transfers.
- **Settings** — terminal appearance, sync, app-lock, updates, about.

### Terminal (the core UX)

- Renders the **xterm fork** `TerminalView` (works on Android).
- **Accessory key bar** docked above the soft keyboard: `Esc`, `Tab`, `Ctrl`,
  `Alt`, arrow keys, `/ - | ~`, `Ctrl+C`, and a Snippets/history launcher.
  `Ctrl`/`Alt` are sticky modifiers (tap to arm, applies to next key).
- **Pinch-to-zoom** adjusts font size (persisted on release, like desktop).
- Mobile-native text selection → copy; paste from the accessory bar / context
  menu.
- Session lifecycle reuses `SessionProvider`; auto-reconnect on resume.

### SFTP (single panel)

Reuses `SftpPanelProvider`, `SftpFileOpsService`, `SftpTransferService`.
Upload uses the SAF file picker (`file_selector`); download writes via SAF.
Context menu: Open / View / Rename / Delete / Permissions / New folder. The
dual-panel "copy to target" matrix is desktop-only and omitted.

## Security

- **Secure storage:** `flutter_secure_storage` → Android Keystore. Keys
  unchanged (`pw_<hostId>`, `pp_<keyId>`, `sync_passphrase`).
- **TOFU:** unchanged — `KnownHostsProvider` + trust dialog adapted to mobile.
- **App-lock:** `local_auth` (fingerprint/face). Gate on app launch and on
  return from background after a configurable timeout (default: immediate).
  Lifecycle hook via `WidgetsBindingObserver`. Fallback to device PIN where
  biometrics are unavailable; setting to disable.
  **Known tradeoff:** desktop dropped `local_auth` in 0.1.35 to shrink bundles;
  with a single shared `pubspec.yaml`, re-adding it for mobile reintroduces its
  native plugins to the desktop bundles too. v1 decision: accept the small
  re-add (and only invoke `local_auth` on Android); revisit per-platform
  dependency isolation only if the desktop bundle-size delta proves material.
- **Sync:** existing client-side AES-256-GCM cloud sync and P2P QR
  (`P2PSyncEncryption`) reused verbatim.

## Milestones

1. **M1 — Android target + build green.** `flutter create --platforms=android`,
   `platform/` abstractions, route desktop-plugin calls through them, branch in
   `main.dart`, empty `MobileApp` shell. **Exit:** debug APK builds and runs;
   desktop builds unchanged; `flutter analyze` clean.
2. **M2 — Terminal MVP.** Hosts list + detail + connect, mobile `TerminalView`,
   accessory key bar, multi-session strip, pinch-zoom. **Exit:** connect to a
   real SSH host and work interactively.
3. **M3 — Sync import.** Cloud sync + P2P QR scan import hosts/keys from
   desktop. **Exit:** scan desktop QR → hosts appear → connect.
4. **M4 — SFTP + snippets/history.** Single-panel SFTP with SAF transfers;
   snippets + command-history insert.
5. **M5 — Security + polish.** Biometric app-lock, TOFU dialog, appearance
   settings, in-app update check (or hide), release APK signing.

## Risks & spikes (do first)

- **Spike 1 (M1, blocking):** add the Android target and build a debug APK with
  all current dependencies present — confirm `window_manager` /
  `hotkey_manager` / `local_notifier` / `flutter_pty` / `sqlite3_flutter_libs`
  / `webview_flutter` don't break the Gradle build. Expectation: green (desktop
  plugins skip Android native), but verify before building UI.
- **Spike 2 (M2):** validate xterm-fork rendering + soft-keyboard input + the
  accessory key bar against a real SSH session early — this is the highest UX
  risk.
- **Background execution:** Android may kill SSH sockets when the app is
  backgrounded. v1 accepts this and auto-reconnects on resume; a foreground
  service is a later consideration, not v1.
- **Min SDK / NDK:** no native cross-compile needed in v1 (RDP/VNC deferred).
  Pick a sane `minSdkVersion` (Flutter default) and document it.
- **Regression guard:** every change to shared code must keep desktop
  (macOS/Windows/Linux) building and tests passing.

## Testing

- Reuse existing unit tests for shared services/providers (must stay green).
- New widget tests for: accessory key bar (modifier/sticky behavior, key
  emission), mobile session view, single-panel SFTP list.
- Manual: a documented checklist per milestone exit criterion (real SSH host,
  real desktop→mobile QR sync).
- `flutter analyze` clean across the whole repo.

## Success criteria (v1)

Install the APK on Android → import hosts from desktop via sync → connect over
SSH → type fluently using the accessory key bar → browse and transfer files
over SFTP → insert a snippet → app re-locks behind biometrics on resume.
`flutter analyze` is clean and the desktop builds are unaffected.
