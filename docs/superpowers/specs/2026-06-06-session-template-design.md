# Session Template / Per-host Preset — Design

**Date:** 2026-06-06
**Status:** Approved

## Problem

Every SSH session starts identical: login shell in `$HOME`, global terminal
theme/font, global TERM type, global tmux setting. Operators managing many
hosts want per-host presets — jump straight into the project directory with
the right env vars, run a startup command, make production hosts visually
distinct (red theme), and force tmux or a legacy TERM on specific boxes.
`Host.autoRecord` already covers the recording half of this roadmap item
(P0 #2); this design covers the rest.

## Goals

- Per-host **working directory** (`cd` on connect) and **env vars**
  (`export` on connect), delivered invisibly — no echo in the terminal, no
  trace in recordings.
- Per-host **startup snippet** (multi-line command text), typed **visibly**
  into the shell after setup — it is user-authored content and should be
  auditable on screen.
- Per-host **terminal theme / font family / font size** overrides falling
  back to the global Settings → Terminal values.
- Per-host **TERM type** and **tmux** overrides falling back to the global
  settings (the per-host override the 2026-06-05 terminal-emulation spec
  explicitly deferred).
- All fields optional; a host with none set behaves exactly as today.
- Fields ride the existing Supabase/P2P sync payload with cross-version
  tolerance.

## Non-goals

- A reusable named `SessionTemplate` entity shared by multiple hosts
  (rejected: roadmap says "extend Host model"; copy-host covers reuse).
- Template delivery on non-bash/zsh shells (fish, Windows servers) — the
  invisible handshake is bash/zsh-only by design; setup is skipped there,
  same as shell integration today.
- Per-host charset selection (separate roadmap item).
- Templates for local terminal sessions (no `Host`).
- Re-running the template on theme-unrelated host edits; setup applies at
  shell open only (connect and auto-reconnect). Theme/font overrides apply
  live, since the render layer watches providers.

## Model changes

`Host` (`app/lib/models/host.dart`) — new fields, all defaulting to
"no override":

| Field | Type | Default | Meaning |
|---|---|---|---|
| `workingDir` | `String?` | null | `cd -- '<dir>'` on connect (hidden) |
| `envVars` | `Map<String, String>` | `{}` | `export K='v'` on connect (hidden) |
| `startupSnippet` | `String?` | null | typed visibly after setup |
| `terminalThemeId` | `String?` | null | theme name from the 44-theme catalog; null = global |
| `fontFamily` | `String?` | null | null = global `terminalFont` |
| `fontSize` | `double?` | null | null = global `fontSize` |
| `termType` | `String?` | null | null = global `terminalType` |
| `tmuxOverride` | `bool?` | null | null = global `tmuxEnabled`; true/false forces |

- `toJson` writes all fields; `fromJson` is tolerant per the existing
  pattern (missing/malformed → default, e.g.
  `(json['envVars'] as Map?)?.cast<String, String>() ?? const {}`), so old
  payloads load and cross-version sync cannot abort list loading.
- `copyWith` gains the new fields; nullables use the `_Unset` sentinel
  pattern already in the file.
- New getter `bool get hasTemplateSetup` →
  `workingDir != null || envVars.isNotEmpty || startupSnippet != null`
  (drives whether the handshake runs when shell integration is off — the
  snippet needs the handshake too, since DONE is its send trigger).
- Env var keys are validated at edit time against
  `[A-Za-z_][A-Za-z0-9_]*`; values are single-quote-escaped
  (`'` → `'\''`) at payload-build time. `workingDir` is escaped the same
  way.
- Sync: `SyncService.buildPayload` strips only `detectedOs`; the new fields
  ride along unchanged.

## Delivery mechanism

Reuses the invisible-injection handshake from
`2026-06-03-invisible-shell-integration-design.md` — readiness detection
(`InjectionReadiness`), bootstrap (`stty -echo` + `read -rs`), payload
`eval`, `InjectionGate` discard. One mechanism, one payload, one DONE
sentinel.

Changes in `ShellIntegrationService` (pure, unit-testable):

- `buildPayloadLine()` grows optional parameters
  (`{String? workingDir, Map<String, String> envVars, bool includeInstaller}`)
  and assembles a **single line** (the payload is consumed by `read -rs`
  into one variable, so it must not contain raw newlines):

  ```
  [SI installer if includeInstaller]; cd -- '<dir>' 2>/dev/null || __ys_td=1;
  export K1='v1' K2='v2'; printf '__YS_%s__\n' DONE;
  [ -n "$__ys_td" ] && printf 'yourssh: working dir not found: <dir>\r\n';
  unset __ys_td
  ```

  Order: installer → cd → exports → DONE → cd-failure warning. The warning
  printf sits **after** the DONE sentinel so it survives the gate's discard
  and renders in the terminal (matching the agent-forwarding-refused
  warning pattern); everything before DONE is discarded as today.

Changes in `SshService.openShell`:

- The handshake launches when `siOn || host.hasTemplateSetup` (today: only
  `siOn`). When SI is off the payload simply omits the installer.
- On non-bash/zsh shells the bootstrap's `|| printf DONE` branch fires and
  the payload is never evaluated — hidden setup (cd/export) is skipped
  silently, identical to SI behavior. The UI labels those fields
  "bash/zsh only". The **snippet still sends**: DONE arrives via the
  fallback branch, and typed visible text is shell-agnostic.
- **Startup snippet:** when the gate sees DONE (passthrough begins),
  `openShell` writes `startupSnippet` (newline-terminated) to the shell —
  visible, recorded, exactly as if typed. If the handshake is aborted (user
  keystroke first, alt-screen, readiness never confirmed) the snippet is
  **not** sent — the user owns the session.
- **tmux rule:** when the effective tmux setting is on, hidden setup
  (cd/export) still runs — it lands in the attached pane's shell and is
  idempotent — but the **snippet is skipped**: a tmux re-attach would
  re-run it into a live session (non-idempotent, potentially destructive).
- Auto-reconnect re-opens the shell, so the template re-applies, same as a
  fresh connect.

## TERM / tmux overrides

`SessionProvider._doConnect` (line ~157) resolves per-host first:

```dart
useTmux:  host.tmuxOverride ?? tmuxEnabled?.call() ?? false,
termType: host.termType ?? terminalType?.call() ?? 'xterm-256color',
```

No signature changes; the callbacks stay the global fallback.

## Theme / font overrides

`_TerminalWidget` in `app/lib/widgets/terminal_view.dart` currently reads
`settings.terminalTheme` / `settings.fontSize` / `settings.terminalFont`
directly (lines ~145, ~176, ~222, ~252). A small resolver replaces those
reads:

- Look up the **fresh** `Host` by `session.host.id` via `HostProvider`
  (the session's snapshot goes stale after `copyWith` — same pattern as
  `SessionTab`), falling back to the snapshot, then resolve
  `host.terminalThemeId ?? settings.terminalTheme` (and font family/size
  likewise). Unknown theme names fall back to the global theme via the
  existing `terminalThemeByName` fallback.
- Because the widget already rebuilds on provider changes, editing a host's
  theme recolors its open sessions live.
- `local_terminal_pane.dart` and `recording_player_widget.dart` keep
  reading globals (no host).

## UI — HostDetailPanel

New **SESSION TEMPLATE** section below the existing SESSION card:

- **Working directory** — single-line text field.
- **Env vars** — editable key/value rows (add/remove); invalid keys show an
  inline error and block save.
- **Startup snippet** — multi-line text field with a "skipped when tmux is
  on; bash/zsh only" helper text.
- **Terminal theme** — dropdown: "Follow global" + the 44-theme catalog.
- **Font family / size** — dropdown reusing the font list from
  `TerminalAppearanceControls` + numeric size field; "Follow global"
  default.
- **TERM type** — dropdown: "Follow global", `xterm-256color`, `xterm`,
  `linux`, `vt100` (same presets as Settings).
- **tmux** — dropdown: "Follow global" / "On" / "Off".

State init and save follow the existing `autoRecord`/`agentForwarding`
pattern in the panel (init lines ~53–80, save ~134–141).

## Testing

- **Pure unit (no IO):**
  - Payload builder: escaping (`'` in dir/values), key validation, ordering
    (installer → cd → export → DONE → warning), single-line invariant,
    installer-less payload when SI off, empty template → unchanged payload.
  - `Host` JSON round-trip with all new fields; forward-compat (missing
    fields → defaults; malformed `envVars` → empty map); `copyWith`
    set/clear via `_Unset`.
  - Effective TERM/tmux resolution (override vs global fallback).
- **Handshake/gate tests** (extend the existing SI test suite with a fake
  shell): SI off + template on still injects; non-bash bootstrap path skips
  setup; cd-failure warning survives the gate; snippet written exactly once
  after DONE; snippet suppressed on abort and when tmux is on.
- **Widget test:** SESSION TEMPLATE section saves fields onto the host;
  invalid env key blocks save.
