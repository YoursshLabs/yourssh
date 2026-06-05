# Quick Wins Bundle — Design

**Date:** 2026-06-05
**Status:** Approved
**Scope:** Four small roadmap polish items shipped as one bundle: middle-click tab close, duplicate port-forward rule, distro-level host OS icons (host list + session tabs), and locking in the existing empty-password SSH behavior with tests.

## Background

These items come from the 2026-06-05 feature-gap research pass in `docs/roadmap.md` (Polish section). Exploration findings that shaped the scope:

- The host list **already** shows OS icons (`_osIcon` in `hosts_dashboard.dart` with `assets/os/{linux,macos,windows}.svg`); the gap is distro-level granularity and session tabs.
- Empty-password SSH **already works**: `HostProvider.addHost`/`updateHost` skip saving blank passwords (`password.isNotEmpty` guard) and `SshService` passes `onPasswordRequest: () => password ?? ''`, so an empty string reaches the server. Only tests are needed.

## 1. Middle-click closes a session tab

**Where:** `_SessionTab` in `app/lib/screens/main_screen.dart` (GestureDetector at ~line 1381, which already wires `onTap` / `onDoubleTap` / `onSecondaryTapUp`).

**Behavior:**
- Add `onTertiaryTapUp`: if the tab is **not pinned**, call `widget.provider.closeSession(widget.session.id)` — the same path as the hover close button.
- Pinned tabs ignore middle-click (consistent with the close button being hidden while pinned; close stays reachable via the right-click menu).
- The pinned Home/SFTP tabs are separate widgets and are not affected.

## 2. Duplicate port-forward rule via context menu

**Where:** `_ForwardTile` in `app/lib/widgets/port_forwarding_screen.dart` (~line 132).

**Behavior:**
- Add `onSecondaryTapUp` opening a `showMenu` context menu with three entries: **Duplicate**, **Edit**, **Delete**. Edit and Delete reuse the tile's existing callbacks (`onEdit`, the hover-delete logic); the menu follows the tab-bar context-menu pattern already in `main_screen.dart`.
- **Duplicate** constructs a new `PortForward` (no `copyWith` on the model; use the constructor):
  - new UUID (constructor default),
  - `label` = original label + `" (copy)"`,
  - same `type`, `localHost`, `localPort`, `remoteHost`, `remotePort`, `hostId`,
  - `autoStart: false` (a copy must never race the original on launch),
  - default status (stopped), zero connections,
  - then `PortForwardProvider.add()`.
- Ports are copied verbatim — no auto-increment. Two stopped rules may share a port; the user edits the copy before starting it. Starting both simply surfaces the existing bind-error path.

## 3. Distro-level host OS icons (host list + session tabs)

### Detection

- Today `SshService` runs `uname -s 2>/dev/null || ver` post-connect and stores `"linux"` / `"macos"` / `"windows"` via `HostProvider.updateDetectedOs`.
- New: when the result is Linux, run a second exec — `cat /etc/os-release 2>/dev/null` — and parse the `ID=` field.
- New pure helper `app/lib/services/os_detection.dart` (no Flutter/IO imports, fully unit-testable):
  - `String? parseOsReleaseId(String content)` — extracts `ID=` (handles quoted/unquoted values, missing field → null).
  - `String normalizeDistroId(String id)` — maps known IDs to icon keys: `amzn` → `amazon`, `almalinux` → `alma`, `opensuse-*` / `sles` → `suse`, `rhel` → `redhat`. Unknown IDs → `linux`.

### Storage

- The distro id is written **directly into `Host.detectedOs`** (e.g. `"ubuntu"` instead of `"linux"`). No model change.
- Unknown/unparseable distro keeps `"linux"`. Existing hosts re-detect on their next connect.
- Supabase sync already strips `detectedOs` from the payload (`SyncService.buildPayload`), so the value never leaves the device.

### Icons

- New monochrome SVGs in `app/assets/os/`, matching the style of the existing three: `ubuntu`, `debian`, `fedora`, `centos`, `rocky`, `alma`, `alpine`, `amazon`, `arch`, `suse`, `redhat`.
- The icon-key set and asset lookup move into `os_detection.dart` as `kOsIconKeys` + `String? osIconAsset(String? detectedOs)` (returns `assets/os/<key>.svg` or null), shared by the dashboard and the tab bar. `hosts_dashboard.dart` (~line 513) drops its private `_osAssets` set in favor of the helper; anything outside the set keeps the `Icons.dns` fallback.

### Session tabs

- `_SessionTab` shows a 14 px OS icon before the title for SSH sessions: look up the `Host` via `HostProvider` by the session's host id and resolve the asset through `osIconAsset` from `os_detection.dart`.
- Local shell tabs keep the existing laptop icon. Sessions with no `detectedOs` show no OS icon (unchanged look).

## 4. Empty-password SSH — tests only

No behavior change. Lock in the current behavior:

- Provider test: `addHost`/`updateHost` with an empty or null password never call `StorageService.savePassword`; a non-empty password does (mock storage).
- Document the connect-side contract in the test name/comments: a host with no stored password authenticates with `''` via `onPasswordRequest`.
- Roadmap: remove the "Auth: allow empty-password SSH" polish bullet (already works).

## Testing

| Item | Test |
|---|---|
| Middle-click close | Widget test: pump the tab bar with a fake session, simulate `TestGesture` with `kTertiaryButton` on the tab → session closed; repeat on a pinned tab → still open. |
| Duplicate rule | Extend `app/test/widgets/port_forwarding_screen_test.dart`: right-click a tile → menu appears → tap Duplicate → provider holds 2 rules: new id, label ends in `" (copy)"`, `autoStart == false`, same ports/hosts. |
| OS detection | Unit tests for `parseOsReleaseId` (real-world os-release samples: quoted, unquoted, missing ID) and `normalizeDistroId` (aliases + unknown → `linux`). Provider-level test that a detected distro id persists via `updateDetectedOs`. |
| Empty password | Provider test with mock storage as described in §4. |

## Out of scope

- Clearing a stored password from the edit dialog (leaving the field blank keeps the old password) — noted as a possible future polish item, not part of this bundle.
- Auto-incrementing ports on duplicate.
- Distro detection over anything other than `/etc/os-release` (no `lsb_release`, no `/etc/redhat-release` fallbacks).
