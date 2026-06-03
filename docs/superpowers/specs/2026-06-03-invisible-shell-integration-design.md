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

1. **Readiness detection** (`InjectionReadiness`, pure): timing heuristics
   are not enough — a MOTD stalling mid-line ("Last login:" … reverse-DNS
   pause) looks exactly like a prompt, and instant-prompt frameworks
   (powerlevel10k) paint a prompt long before the shell reads input.
   Injecting then gets the line echoed by the kernel (canonical mode)
   mid-MOTD and re-echoed by zle — mangled output, observed in the field.
   The reliable signal is the **bracketed-paste toggle**: modern zsh/bash
   emit `ESC[?2004h` exactly when the line editor starts reading and
   `ESC[?2004l` when it stops. Toggle ON + 250 ms of settle (redraw burst
   over) → inject. Sequences split across chunks are handled with a 16-char
   carry-over scan tail.
2. **Probe fallback** for shells without bracketed paste (bash ≤ 5.0): after
   1.2 s of silence — and a 2.5 s floor so instant-prompt frameworks have
   revealed themselves — send a bare `\n`. A real prompt answers with a
   prompt-like tail (escape-stripped text ending in `$ # % > ❯ ➜ »`); MOTD
   in progress only produces a kernel `\r\n` echo. Four unanswered probes →
   give up: a missing integration beats junk in the terminal. Guards: an
   alt-screen entry (`ESC[?1049h`/`ESC[?47h` — vim/less) or any user
   keystroke before the handshake aborts injection entirely.
   Pre-injection output flows straight to the terminal — MOTD is never
   delayed.
3. Write the bootstrap line, activate the gate, start a 2 s done-timeout.
4. Stdout listener order per chunk: hookBus transform (unchanged) → gate →
   emitted text goes to `terminal.write` + recording + notifications. Held
   text reaches none of them until flush, so recordings stay clean too.
5. On DONE: the gate discards the echo head and emits only the tail (which
   starts with the newline carried by the DONE printf). The shell's next
   prompt renders below the old one — visually identical to the user having
   pressed Enter once. Nothing junk-related ever reaches the terminal or the
   recording.
6. Timeout / shell close while holding: `flush()` (held text shown as-is,
   sentinels stripped), no payload.

## Degradation matrix

| Environment | Result |
|---|---|
| bash / zsh (incl. highlight plugins, fancy prompts) | Invisible — looks like one extra Enter press |
| sh / dash / ksh | Clean (bootstrap echo discarded, payload skipped) |
| fish | Parse error + bootstrap line visible after 2 s flush timeout (better than today) |
| tmux | Sentinels are plain text → pass through tmux; the app never renders the junk, but tmux's server-side grid still contains it, so a tmux-initiated full redraw (pane switch/resize) may resurrect ~2 junk rows — known limitation |
| Readiness never confirmed (exotic shell, no prompt) | Injection skipped entirely — clean terminal, no integration |
| Full-screen app / user typing before handshake | Injection aborted — never types into vim or a half-typed command line |
| Long-running `initialCommand` (e.g. `tail -f`) | No prompt answer → probes exhausted → injection skipped (was: script fed into the command's stdin) |

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
- Full app-side logic (readiness + gate) simulated against real PTYs in six
  scenarios: fast/slow zsh (powerlevel10k incl. instant prompt), fast/slow
  bash 3.2 (probe path), and the field-failure mid-line MOTD stall on both —
  asserting no junk, MOTD intact, hooks installed.

## Out of scope

- Hiding the `tmux new-session` / `initialCommand` echo (separate, pre-existing).
- fish shell support.
- Cleaning tmux's internal grid after redraw.
