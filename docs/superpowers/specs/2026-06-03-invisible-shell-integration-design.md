# Invisible Shell Integration Injection — Design

**Date:** 2026-06-03
**Status:** Approved

## Problem

On every SSH connect with shell integration enabled, `SshService.openShell` writes
the full OSC 7/133 hook-installer script (~700 chars) to the shell's stdin
(`ssh_service.dart:386`). The remote PTY echoes everything "typed", so the user
sees the entire script dumped into the terminal after the first prompt. Goal:
make the injection **completely invisible** — not a single frame where the
script is painted.

## Constraints

- No artifacts left on the server (no staged rc files).
- MOTD and first prompt must render immediately (no withholding of pre-injection
  output).
- Must survive real-world zsh setups (zle redraw, zsh-syntax-highlighting
  interleaving SGR codes into the echo) — therefore **no byte-matching of the
  echoed script**.
- Graceful degradation on non-bash/zsh shells and under tmux.

## Approach: two-phase handshake + client-side withhold & discard

Three cooperating pieces:

### 1. Protocol (two sentinels, two writes)

**Bootstrap line** (~100 chars) replaces the direct script write:

```sh
[ -n "$BASH_VERSION$ZSH_VERSION" ] && { stty -echo 2>/dev/null; printf '__YS_%s__' RDY; IFS= read -rs __ys; eval "$__ys"; unset __ys; stty echo 2>/dev/null; } || printf '__YS_%s__\n' DONE
```

- The `printf '__YS_%s__' RDY` trick guarantees the literal sentinel
  `__YS_RDY__` never appears in the *echo* of the command line — the app can
  scan the output stream for sentinels without false-positives.
- bash/zsh: disables tty echo, prints `__YS_RDY__`, then blocks in `read -rs`.
  The explicit `stty -echo` BEFORE the RDY printf closes the race where the
  payload arrives after RDY but before `read -s` has switched the tty itself
  — the kernel would echo it (reproduced on real bash).
- POSIX sh/dash/ksh: `[ … ]` is false → `||` branch prints `__YS_DONE__`
  immediately; the app skips the payload and still cleans up the echo.

**Payload line** (sent only after `__YS_RDY__` is seen): the existing
hook-installer body from `buildInjectionScript()` (unchanged semantics:
`__yourssh_si` guard, zsh precmd/preexec, bash PROMPT_COMMAND/DEBUG trap),
terminated by `printf '__YS_%s__\n' DONE`. Because `read -rs` is consuming
it, the payload is **never echoed** — immune to zle redraw/highlighting.
The trailing newline after DONE lands both the remote shell and the app on
a fresh line (col 0), so the next prompt renders in sync on both sides.

### 2. `InjectionGate` — new pure class

Lives next to `ShellIntegrationService` (no Flutter/IO deps; fully
unit-testable). State machine `holding → passthrough`:

- `feed(text) → GateResult{ emit: String?, sendPayload: bool }`
  - While holding: accumulate text into a buffer; scan the *accumulated* buffer
    for sentinels so a sentinel split across two chunks still matches.
  - First `__YS_RDY__` → `sendPayload: true` (exactly once).
  - `__YS_DONE__` → **discard** the head (everything before the sentinel — it
    is just the bootstrap echo + RDY) and emit only the tail after the
    sentinel. Discarding, rather than writing the head and erasing it with
    cursor math, keeps the app-side cursor in sync with where the remote
    shell believes it is; erase-based cleanup desyncs the two and fancy
    prompts (powerlevel10k etc.) then paint over the wrong rows — observed in
    the field as mangled MOTD/prompt text. `DONE` without prior `RDY` is the
    non-bash/zsh path: discard, never send payload.
  - Over-hold guard (`maxHold`, bootstrap length × 4): a head larger than
    plausible echo means real server output (late MOTD) landed inside the
    hold window — emit it stripped of sentinels instead of discarding,
    rendered exactly as if it was never held.
  - In passthrough: `emit` is just the input text.
- `flush() → String` — timeout / shell-closed path: strip sentinels, emit
  buffer as-is, switch to passthrough (degrades to today's behavior, but the
  junk is one short bootstrap line instead of the full script).

### 3. `SshService.openShell` wiring

1. **Quiescence wait**: do not write the injection right after channel open.
   Arm a 300 ms timer only when a chunk looks prompt-like (does **not** end
   with a newline — cursor resting mid-line). A chunk ending in `\n` means
   the server is still printing (banner, late "Last login:" MOTD) — keep
   waiting; a 3 s cap timer is the backstop for hosts that never settle.
   Pre-injection output flows straight to the terminal — MOTD is never
   delayed.
2. Write the bootstrap line, activate the gate, start a 2 s done-timeout.
3. Stdout listener order per chunk: hookBus transform (unchanged) → gate →
   emitted text goes to `terminal.write` + recording + notifications. Held
   text reaches none of them until flush, so recordings stay clean too.
4. On DONE: the gate discards the echo head and emits only the tail (which
   starts with the newline carried by the DONE printf). The shell's next
   prompt renders below the old one — visually identical to the user having
   pressed Enter once. Nothing junk-related ever reaches the terminal or the
   recording.
5. Timeout / shell close while holding: `flush()` (held text shown as-is,
   sentinels stripped), no payload.

## Degradation matrix

| Environment | Result |
|---|---|
| bash / zsh (incl. highlight plugins, fancy prompts) | Invisible — looks like one extra Enter press |
| sh / dash / ksh | Clean (bootstrap echo discarded, payload skipped) |
| fish | Parse error + bootstrap line visible after 2 s flush timeout (better than today) |
| tmux | Sentinels are plain text → pass through tmux; the app never renders the junk, but tmux's server-side grid still contains it, so a tmux-initiated full redraw (pane switch/resize) may resurrect ~2 junk rows — known limitation |
| Long-running `initialCommand` (e.g. `tail -f`) | Bootstrap is consumed as that command's stdin — pre-existing flaw, unchanged |

## Testing

- `shell_integration_service_test.dart`: bootstrap/payload format — guard
  correctness, literal sentinels absent from the bootstrap source text,
  payload ends with the DONE printf, hook-installer body unchanged.
- New `InjectionGate` tests: sentinel split across chunks, DONE-without-RDY,
  duplicate-RDY fires `sendPayload` once, timeout flush, head discard vs
  over-hold emit, passthrough after DONE, tail emission after DONE in the
  same chunk.
- SshService glue (quiescence/cap/done timers, payload write) stays thin;
  all decision logic lives in the pure gate/service for unit testing.
- Protocol verified end-to-end against real zsh/bash/dash PTYs (payload never
  echoed, hooks installed, `__ys` unset, fresh line after DONE).

## Out of scope

- Hiding the `tmux new-session` / `initialCommand` echo (separate, pre-existing).
- fish shell support.
- Cleaning tmux's internal grid after redraw.
