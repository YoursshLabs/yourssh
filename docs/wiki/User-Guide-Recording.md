# Recording

Record your terminal sessions to Asciinema v2 (`.cast`) files and replay them later.

<!-- SCREENSHOT: Recording Library screen showing a list of recordings with host names and timestamps, one expanded with the player widget visible -->

## Starting a Recording

Click the **record** (●) button in the session toolbar. A red indicator appears in the tab while recording is active.

To stop, click the toolbar button again or close the session.

## Auto-Record

Enable **Auto-record** per host in the host detail panel. Every new session for that host starts recording automatically.

## Secret Redaction

Recordings mask secrets before they are written to disk, so a `.cast` you
share for a demo or runbook doesn't leak a `PGPASSWORD=…` echoed
mid-session. Masked patterns match the audit log's redaction:
`key=value`-style passwords/tokens/API keys, `Authorization: Bearer` tokens,
`sshpass -p`, mysql/mariadb attached `-p`, `redis-cli -a`, and passwords in
URLs — each replaced with `[REDACTED]`.

Redaction is **on by default** and controlled in two places:

- **Settings → Recording → Redact secrets in recordings** — the global
  switch.
- **Host detail panel → SESSION → Redact secrets in recordings** — a
  per-host opt-out (only effective while the global switch is on).

Local shell recordings follow the global switch alone. The setting is
sampled when a recording starts; flipping it mid-recording applies to the
next one.

Two trade-offs to know about:

- Replay timing becomes per-line rather than per-keystroke (output is
  buffered briefly so secrets split across chunks can still be matched —
  this also hides your typing rhythm, which is itself a side-channel).
- Redaction is defense-in-depth, not a guarantee: a token interleaved with
  ANSI color codes, or one outside the known patterns, won't be caught.

## Recording Library

Open **Recordings** from the sidebar to see all saved `.cast` files, organized by host. Click any entry to open the player.

### Player Controls

| Control | Action |
|---|---|
| Play / Pause | Space or the play button |
| Speed | 0.5× – 5× via the speed dropdown |
| Seek | Click anywhere on the progress bar |

## File Location

Recordings are saved to:

```
~/.yourssh/recordings/<username>@<hostname>/session_YYYY-MM-DD_HH-mm-ss.cast
```

## Related Pages

- [Terminal](User-Guide-Terminal) — recording is started from the terminal toolbar
