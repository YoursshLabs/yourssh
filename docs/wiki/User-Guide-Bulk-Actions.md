# Bulk Actions

Act on many hosts at once from the hosts dashboard: open a tab per host, run one command everywhere in parallel, or push files to the same path on every server.

<!-- SCREENSHOT: Hosts dashboard in SELECT mode with several hosts checked and the bulk action bar visible -->

## Selecting Hosts

1. Click **SELECT** in the dashboard toolbar — every host card gets a checkbox.
2. Tick the hosts you want, or use **SELECT ALL** — it respects the active smart filter, so you can filter first and select only the matches.
3. **CLEAR** empties the selection; **DONE** or **Esc** leaves select mode.

The action bar shows the selection count and the three bulk actions.

## Connect All

Opens an SSH tab for every selected host. Hosts that already have a connected session are skipped, and opening more than 5 tabs asks for confirmation first.

## Run Command

Run one command — free text or a saved snippet — on every selected host in parallel:

- Commands run with bounded concurrency and a **30-second per-host timeout**; one host failing never stops the others.
- Each host row shows live status, exit code, and duration; expand a row to see its stdout/stderr.
- The **Diff** tab groups identical outputs against a baseline (any group can be promoted to baseline) and can side-by-side compare any two hosts — handy for spotting the one server with a different config.

## Push Files

Upload files or folders to one remote path on every selected host:

- The destination directory is created if it doesn't exist; existing files are overwritten.
- Per-host byte progress, with cancel.

## Cancelling Mid-Run

Closing a bulk dialog while work is still running asks for confirmation: queued hosts are cancelled, while in-flight operations finish and record their real result.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — manage hosts, groups, tags, and the smart filter
- [Terminal](User-Guide-Terminal) — broadcast mode (type into several open sessions at once)
