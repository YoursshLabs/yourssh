# Recording

Record your terminal sessions to Asciinema v2 (`.cast`) files and replay them later.

<!-- SCREENSHOT: Recording Library screen showing a list of recordings with host names and timestamps, one expanded with the player widget visible -->

## Starting a Recording

Click the **record** (●) button in the session toolbar. A red indicator appears in the tab while recording is active.

To stop, click the toolbar button again or close the session.

## Auto-Record

Enable **Auto-record** per host in the host detail panel. Every new session for that host starts recording automatically.

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
