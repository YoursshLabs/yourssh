# Terminal Emulation Type — Design

**Date:** 2026-06-05
**Status:** Approved

## Problem

The TERM type sent in the SSH PTY request is hardcoded to `xterm-256color`
(`app/lib/services/ssh_service.dart:382`). Users connecting to legacy devices
(network appliances, old Unix systems) need to present a simpler terminal type
(`vt100`, `linux`, `xterm`) so the server doesn't emit escape sequences the
device-side tooling can't handle.

## Decision

A single **global** setting, **SSH sessions only**:

- Lives in Settings → Terminal as a dropdown.
- Options: `xterm-256color` (default), `xterm`, `linux`, `vt100`.
- Applies to **new** SSH connections only; open sessions keep the TERM they
  were opened with (the PTY type is fixed at `pty-req` time). Auto-reconnect
  re-opens the shell, so a reconnected session picks up the current setting.
- The local terminal keeps the hardcoded `TERM=xterm-256color`
  (`local_shell_service.dart`): a local PTY is always a modern machine, so a
  degraded TERM only loses colors.

Rejected alternatives:

- **Per-host field** — user explicitly chose global; can be revisited later as
  a per-host override if a real need shows up.
- **Free-text input** — YAGNI; the four presets cover real-world use and avoid
  typo'd TERM values silently breaking remote sessions.

## Changes

Follows the existing `tmuxEnabled` settings → callback → service pattern; no
new dependencies.

1. **`SettingsProvider`** (`app/lib/providers/settings_provider.dart`)
   - New field `String terminalType = 'xterm-256color'`.
   - `_load()` reads `prefs.getString('terminalType') ?? 'xterm-256color'`.
   - `save()` gains an optional `terminalType` parameter and persists it.

2. **`SshService.openShell`** (`app/lib/services/ssh_service.dart`)
   - New parameter `String termType = 'xterm-256color'`.
   - Passed as `SSHPtyConfig(type: termType, ...)` replacing the hardcoded
     string. The dartssh2 fork already supports a configurable type.

3. **`SessionProvider`** (`app/lib/providers/session_provider.dart`)
   - New callback `String Function()? terminalType` next to `tmuxEnabled`.
   - The `openShell` call site passes
     `termType: terminalType?.call() ?? 'xterm-256color'`.

4. **`main.dart`**
   - Wire `_sessionProvider.terminalType = () => _settingsProvider.terminalType;`
     next to the existing `tmuxEnabled` wiring.

5. **Settings UI** (`app/lib/widgets/settings_screen.dart`)
   - Dropdown row at the top of the existing `Terminal` section (above
     `TerminalAppearanceControls`), listing the four TERM values.
   - Subtitle: "Applies to new SSH connections".

Out of scope: `TerminalConfigPanel` side panel (it hosts live-applying
appearance controls only — TERM is not live, so surfacing it there would
mislead), `Host` model, sync payload, JS plugin API.

## Testing

- `SettingsProvider`: defaults to `xterm-256color` when unset; persists and
  reloads a changed value.
- `SessionProvider`/`SshService`: shell opens with the TERM value returned by
  the callback, and falls back to `xterm-256color` when the callback is unset
  (use the existing test harness around `openShell` if present; otherwise test
  at the provider layer).
