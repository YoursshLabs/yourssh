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

## Approach: two-phase handshake + client-side withhold & erase

Three cooperating pieces:

### 1. Protocol (two sentinels, two writes)

**Bootstrap line** (~100 chars) replaces the direct script write:

```sh
[ -n "$BASH_VERSION$ZSH_VERSION" ] && { printf '__YS_%s__' RDY; IFS= read -rs __ys; eval "$__ys"; unset __ys; } || printf '__YS_%s__' DONE
```

- The `printf '__YS_%s__' RDY` trick guarantees the literal sentinel
  `__YS_RDY__` never appears in the *echo* of the command line — the app can
  scan the output stream for sentinels without false-positives.
- bash/zsh: prints `__YS_RDY__`, then blocks in `read -rs` (raw, **no echo**).
- POSIX sh/dash/ksh: `[ … ]` is false → `||` branch prints `__YS_DONE__`
  immediately; the app skips the payload and still cleans up the echo.

**Payload line** (sent only after `__YS_RDY__` is seen): the existing
hook-installer body from `buildInjectionScript()` (unchanged semantics:
`__yourssh_si` guard, zsh precmd/preexec, bash PROMPT_COMMAND/DEBUG trap),
terminated by `printf '__YS_%s__' DONE`. Because `read -rs` is consuming it,
the payload is **never echoed** — immune to zle redraw/highlighting.

### 2. `InjectionGate` — new pure class

Lives next to `ShellIntegrationService` (no Flutter/IO deps; fully
unit-testable). State machine `holding → passthrough`:

- `feed(text) → GateResult{ emit: String?, sendPayload: bool }`
  - While holding: accumulate text into a buffer; scan the *accumulated* buffer
    for sentinels so a sentinel split across two chunks still matches.
  - First `__YS_RDY__` → `sendPayload: true` (exactly once).
  - `__YS_DONE__` → strip all sentinel occurrences from the buffer, emit the
    whole buffer, switch to passthrough. `DONE` without prior `RDY` is the
    non-bash/zsh path: flush, never send payload.
  - In passthrough: `emit` is just the input text.
- `flush() → String` — timeout / shell-closed path: strip sentinels, emit
  buffer as-is, switch to passthrough (degrades to today's behavior, but the
  junk is one short bootstrap line instead of the full script).

### 3. `SshService.openShell` wiring

1. **Quiescence wait**: do not write the injection right after channel open.
   Wait for the first output chunk, then 300 ms of silence (cap: 3 s total)
   so MOTD + first prompt are already rendered. Pre-injection output flows
   straight to the terminal — MOTD is never delayed.
2. Sample `y0 = terminal.buffer.absoluteCursorY` (prompt row), write the
   bootstrap line, activate the gate, start a 2 s done-timeout.
3. Stdout listener order per chunk: hookBus transform (unchanged) → gate →
   emitted text goes to `terminal.write` + recording + notifications. Held
   text reaches none of them until flush, so recordings stay clean too.
4. On DONE: take `emit`, write it to the terminal, sample
   `y1 = absoluteCursorY`, then write the erase sequence
   `\r ESC[{y1−y0}A ESC[0J` (skip the cursor-up when `y1 == y0`) — all within
   the same event-loop turn, i.e. the same paint frame. The echo region
   (prompt row → end of echo) is erased before it is ever painted; the shell's
   next prompt then renders at row `y0`. The erase sequence is also written to
   the recording for replay fidelity.
5. **Over-hold guard**: if the held buffer is suspiciously large
   (> ~4× the bootstrap length — late MOTD burst landed inside the window),
   flush *without* the erase to avoid wiping real output.
6. Timeout / shell close while holding: `flush()`, no erase, no payload.

## Degradation matrix

| Environment | Result |
|---|---|
| bash / zsh (incl. highlight plugins) | Fully invisible |
| sh / dash / ksh | Clean (bootstrap echo erased, payload skipped) |
| fish | Parse error + bootstrap line visible after 2 s timeout (better than today) |
| tmux | Sentinels are plain text → pass through tmux; app-side erase works, but a tmux-initiated redraw (pane switch/resize) may resurrect ~2 junk rows from tmux's grid — known limitation |
| Long-running `initialCommand` (e.g. `tail -f`) | Bootstrap is consumed as that command's stdin — pre-existing flaw, unchanged |

## Testing

- `shell_integration_service_test.dart`: bootstrap/payload format — guard
  correctness, literal sentinels absent from the bootstrap source text,
  payload ends with the DONE printf, hook-installer body unchanged.
- New `InjectionGate` tests: sentinel split across chunks, DONE-without-RDY,
  duplicate-RDY fires `sendPayload` once, timeout flush, sentinel stripping,
  passthrough after DONE, trailing output after DONE in the same chunk.
- SshService glue (quiescence timer, y0/y1 sampling, erase write) stays thin;
  all decision logic lives in the pure gate/service for unit testing.

## Out of scope

- Hiding the `tmux new-session` / `initialCommand` echo (separate, pre-existing).
- fish shell support.
- Cleaning tmux's internal grid after redraw.
