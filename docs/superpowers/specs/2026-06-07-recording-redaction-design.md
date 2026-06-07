# Recording Redaction — Design

**Date:** 2026-06-07
**Status:** Approved
**Roadmap:** P1 → Security & identity → "Recording redaction — regex-mask
tokens/passwords before writing to `.cast`"

## Goal

Mask secrets (passwords, tokens, API keys) in terminal output **before** it is
written to asciicast `.cast` recording files, reusing the shipped
`AuditRedactor` patterns unchanged. A recording shared for a demo or a runbook
must not leak the `PGPASSWORD=…` someone echoed mid-session.

## Why write-time, not post-processing

Terminal output reaches `RecordingService.writeOutput` in arbitrary chunks: a
secret can be split across two events, and command echo arrives one keystroke
per chunk. Three options were considered:

1. **Line-buffered redaction at write time** — *chosen.* Coalesce chunks per
   line before redacting and writing. Catches split secrets and keystroke
   echo; as a side effect it erases keystroke-timing patterns (a known
   side-channel) from recordings.
2. Per-chunk redaction — preserves exact timing but misses any secret that
   straddles a chunk boundary, including all typed echo. Rejected.
3. Post-processing at stop — perfect cross-chunk matching, but the raw
   secrets sit on disk for the whole session and survive an app crash.
   Rejected.

The cost of (1): replay timing becomes per-line (one event per completed
line, or per 500 ms flush window for TUI output) instead of per-chunk. For a
security feature this trade-off was accepted explicitly.

## Toggle model — per-host + global

Mirrors the `shellIntegration` pattern:

- `SettingsProvider.recordingRedactionEnabled` — global, **default `true`**,
  persisted as `recordingRedactionEnabled` in `SharedPreferences`, exposed in
  `save(...)` like `shellIntegrationEnabled`. UI: a switch row in the existing
  **Settings → Recording** section (`settings_screen.dart`, next to
  "Recording path"): *"Redact secrets in recordings"* with a subtitle noting
  replay timing becomes per-line.
- `Host.recordingRedaction` — `bool`, **default `true`**, JSON round-trip
  (missing key → `true`), `copyWith` support. UI: a switch in the host
  panel next to the existing "Auto-record sessions" toggle
  (`host_detail_panel.dart`): *"Redact secrets in recordings"*.
- **Effective value = global AND host.** A host-level `true` cannot override
  a global `false` (same semantics as shell integration).
- Local shell sessions have no `Host` → the global setting alone decides.

## Data flow

```
RecordButton / autoRecord
  └── RecordingProvider.startRecording(session)
        ├── redactionPolicy?.call(session) → bool   (wired in main.dart:
        │     global && (session is SshSession ? session.host.recordingRedaction : true);
        │     null policy (tests) → redaction off, current behavior)
        └── RecordingService.startRecording(…, redact: <bool>)
              └── _ActiveRecording(redact, pending, flushTimer, …)

SshService / LocalShellService output
  └── RecordingService.writeOutput(sessionId, chunk)
        ├── redact == false → write [t,'o',chunk] immediately (today's path,
        │                      byte-for-byte unchanged)
        └── redact == true  → line buffer (below)
```

`RecordingProvider` gains a `bool Function(TerminalSession session)?
redactionPolicy` callback field, wired in `main.dart` (where `recordingStart`
is already wired) so the provider stays free of Settings/Host imports.

The policy is sampled **once at start-recording time**; mid-session toggle
changes apply to the next recording, not the active one.

## Line buffer in `RecordingService`

`_ActiveRecording` gains: `final bool redact`, `final StringBuffer pending`,
`Timer? flushTimer`. `RecordingService` gains a constructor parameter
`flushDelay` (default `Duration(milliseconds: 500)`) so tests drive it with
`fakeAsync`.

`writeOutput(sessionId, chunk)` when `redact` is on:

1. Append `chunk` to `pending`.
2. If `pending` contains `\n`: split at the **last** `\n` (inclusive). The
   complete portion goes through `AuditRedactor.redact()` and is written as
   **one** event `[elapsed, 'o', redacted]` stamped at the current stopwatch
   elapsed (the flush moment). The remainder stays in `pending`.
3. Timer management: `pending` non-empty and no timer running → start
   `flushTimer` with `flushDelay`; `pending` emptied → cancel. The timer is
   **not** reset by subsequent chunks (no debounce): a TUI streaming without
   newlines must still flush at most `flushDelay` after the first buffered
   byte, keeping latency and buffer growth bounded. On fire: redact + write
   the whole `pending` as one event, clear it.
4. `\r` is not a split point — prompt redraws and `\r\n` endings stay inside
   whatever portion they arrive in.

`stopRecording` (and therefore `onShellClosed`): cancel `flushTimer`, flush
the remaining `pending` through `redact()` as a final event, then flush and
close the sink as today.

Timestamps are taken at write time, so they remain monotonically
non-decreasing by construction.

## Redaction engine

`AuditRedactor.redact()` is reused **unchanged**. It already masks:
`key=value` secrets (incl. prefixed `PGPASSWORD=`, quoted multi-word values),
`Authorization: Bearer`, `sshpass -p`, mysql/mariadb attached `-p`,
`redis-cli -a`, and URL userinfo passwords — idempotently.

### Known limitations (accepted, documented here deliberately)

- **ANSI escapes inside a secret break matching.** A token interrupted by
  color/cursor sequences (e.g. a prompt redraw mid-echo) won't match the
  regexes. This feature is defense-in-depth, not a guarantee.
- **A secret straddling a `flushDelay` boundary can leak its tail.** If the
  head of a token is flushed by the timer (e.g. `password=hun` masked) and
  the rest arrives afterwards, the post-timer remainder (`ter2`) is written
  in a later event without context to match. Inherent cost of bounded
  buffering; a larger `flushDelay` shrinks the window.
- Only the `AuditRedactor` pattern families are caught. A bare password typed
  at a hidden prompt never echoes, so it never reaches the recording anyway.
- Coalescing changes the `.cast` event structure (fewer, larger events).
  Players (asciinema, the in-app player) are agnostic to event granularity.
- A secret printed **without a trailing newline** that sits in `pending` is
  still redacted before write — but only when the flush (timer/stop) fires,
  at which point a *following* chunk may have completed the token. Splitting
  at the last newline (not the first) maximizes the joined window.

## Testing

- **`RecordingService`** (`fakeAsync` + temp dir, following the existing
  recording tests):
  - secret split across two chunks (`pass` + `word=hunter2\n`) is masked in
    the written event;
  - a multi-newline chunk is redacted and written as one event;
  - partial line with no newline flushes (redacted) after `flushDelay`;
  - `stopRecording` flushes a pending partial line before closing;
  - `redact: false` output is byte-for-byte today's format (one event per
    chunk, no coalescing);
  - event timestamps are non-decreasing across buffered flushes;
  - header line is unaffected.
- **`Host` model:** `recordingRedaction` JSON round-trip, missing-key default
  `true`, `copyWith` keep/override.
- **`SettingsProvider`:** persistence of `recordingRedactionEnabled`.
- **`RecordingProvider`:** `redactionPolicy` result is passed to the service
  (capturing fake); null policy → `redact: false`.

## Out of scope

- Custom user-defined redaction patterns (future: settings UI for extra
  regexes — would extend `AuditRedactor`, not this feature).
- Redacting *existing* `.cast` files in the library.
- Input (`'i'`) events — recordings only write output events today.
