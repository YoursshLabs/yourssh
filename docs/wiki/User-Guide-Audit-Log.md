# Audit Log

YourSSH keeps a local, secret-safe audit trail of what ran where: every
connect/disconnect and every command issued through the app — bulk runs, AI
tool calls, plugins, snippets, the terminal input bar, and broadcast input
(one row per target host). Open it from the sidebar: **Audit Log**.

> The log records commands sent *through app features*. Keystrokes typed
> directly into a terminal pane are not captured.

## What gets recorded

| Event | When |
|---|---|
| `connect` | A session connects successfully, or finally fails (with the error and attempt count) |
| `disconnect` | You close a live tab, or a session drops (including drops that auto-reconnect) |
| `exec` | A command runs over SSH exec — bulk run, DevOps tools, plugins, AI — tagged with its source and exit code |
| `input` | A command submitted via the terminal input bar, broadcast input, or a plugin |

Internal polling probes (network stats overlay, OS detection) are
deliberately excluded so the log stays meaningful.

## Secret redaction

Commands are scrubbed **before** they are written to disk. Masked patterns
include `password=`/`token=`/`secret=`/`api_key=` values (quoted multi-word
values included, plus prefixed forms like `PGPASSWORD=`), `Authorization:
Bearer` tokens, `sshpass -p`, the mysql family's attached `-p<password>`,
`redis-cli -a`, and passwords inside URLs (`scheme://user:pass@host`). Error
messages stored with failed events pass through the same redaction.

Redaction is best-effort pattern matching — avoid putting secrets on command
lines where you can.

## Viewing and filtering

- Newest events first; filter by **type**, **time range** (Today / 7d / 30d /
  All), or free-text **search** over the command and host.
- Each row shows the timestamp, a colored type chip, `user@host`, the
  (redacted) command, its source, and the exit code.
- **Load more** pages through long histories without skipping rows.

## Export

**CSV** and **JSON** buttons export exactly what the current filter shows,
via a standard save dialog.

## Retention and clearing

Settings → **Audit** sets retention (30 / 90 / 365 days or keep forever —
default 90). Older rows are pruned at app launch. **Clear audit log** (in
Settings or on the Audit screen) deletes everything after a confirmation.

The database lives in the app's local support directory
(`audit.db`) and never syncs anywhere.

## Related Pages

- [Bulk Actions](User-Guide-Bulk-Actions) — parallel runs show up per host
- [Recording](User-Guide-Recording) — full terminal replay, complementary to the audit trail
- [Settings](User-Guide-Settings)
