# Internal Audit Log — Design

**Date:** 2026-06-06
**Status:** Approved

## Problem

The app can touch dozens of hosts in one action (bulk run, AI tool calls,
snippets), but nothing records who ran what, where, and when. For
compliance and incident retrospectives ("which hosts got that command last
Tuesday?") an operator needs a local, queryable, secret-safe audit trail.
Roadmap P0 #1.

## Goals

- Record **connect/disconnect** (incl. connect failures) and **commands**
  with timestamp, host, username, session, source, and exit code.
- Capture every programmatic exec path (bulk run, AI tools, DevOps plugin,
  `ssh.exec` from JS plugins) plus commands the user submits through the
  terminal input bar and snippets inserted via the plugin `sendInput` API.
- **Redact secrets** before anything is written to disk.
- SQLite storage that stays fast at hundreds of thousands of rows.
- Viewer screen with filters (host, type, time range), free-text search,
  and CSV/JSON export of the filtered view.
- Configurable retention with automatic pruning.
- Auditing must **never break SSH operations**: every write is fail-soft.

## Non-goals

- Capturing interactive shell commands typed directly into the terminal
  (requires extending the shell-integration OSC protocol to carry command
  text — separate roadmap follow-up).
- Storing stdout/stderr (secret-leak risk and DB bloat; command + exit
  code only).
- Syncing the audit log (roadmap's "optional sync" — later).
- Multi-user identity / RBAC: "who" on a single-user desktop app is the
  OS user; the recorded `username` is the SSH username used on the host.
- Tamper-proofing (signatures/append-only guarantees beyond SQLite).

## Storage

New dependencies: `sqlite3` + `sqlite3_flutter_libs` (bundles the native
lib on macOS/Windows/Linux; direct SQL, no codegen). Tests use
`sqlite3.openInMemory()` — no device needed.

DB file: `<getApplicationSupportDirectory()>/audit.db` (path_provider is
already a dependency).

```sql
CREATE TABLE IF NOT EXISTS audit_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,          -- epoch ms UTC
  type TEXT NOT NULL,           -- connect | disconnect | exec | input
  host_id TEXT,
  host_label TEXT,              -- denormalized: host may be deleted later
  username TEXT,
  session_id TEXT,
  command TEXT,                 -- redacted before insert
  exit_code INTEGER,
  meta TEXT                     -- JSON: source, error message, …
);
CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit_events(ts);
CREATE INDEX IF NOT EXISTS idx_audit_host ON audit_events(host_id);
```

`meta.source` values: `bulk`, `ai`, `snippet`, `plugin:<name>`,
`input-bar`, `devops`, `app` — set by the call site so the viewer can
distinguish a human-typed command from an AI tool call. `SshService.exec`
cannot know its caller, so it gains an optional `auditSource` parameter
(default `'app'`) that bulk run, AI tools, and the plugin bridges pass
explicitly.

## Components

- **`AuditService`** (`app/lib/services/audit_service.dart`) — owns the DB
  handle; `record(AuditEvent)` (fail-soft: try/catch + `debugPrint`, never
  throws), `query(filter, limit, offset)`, `prune(olderThanDays)`,
  `clearAll()`, `exportCsv(filter)` / `exportJson(filter)`. Single
  connection, WAL mode, inserts via prepared statement.
- **`AuditRedactor`** (`app/lib/services/audit_redactor.dart`) — pure
  (no IO): `redact(String command) → String`. Default patterns:
  `password=`, `passwd=`, `token=`, `secret=`, `api[_-]?key=`,
  `Authorization: Bearer <…>`, `sshpass -p <…>`, `-p<pass>`/`-p <pass>`
  after `mysql`/`psql`/`mariadb`, URL userinfo (`scheme://user:pass@`).
  The matched secret portion is replaced with `[REDACTED]`; the command
  structure stays readable.
- **`AuditEvent`** (`app/lib/models/audit_event.dart`) — immutable row
  model with `toCsvRow()` / `toJson()`.
- **`AuditProvider`** (`app/lib/providers/audit_provider.dart`) — filter
  state (host, type, time range, search text), lazy page cache
  (LIMIT/OFFSET 200), exposes `events`, `loadMore()`, `refresh()`,
  `clearAll()`, export pass-throughs.
- **`AuditScreen`** (`app/lib/screens/audit_screen.dart`) + new
  `NavSection.audit` sidebar entry — newest-first table (time, type chip,
  host, command, exit code), filter row (host dropdown, type dropdown,
  Today/7d/30d/All presets, search field), Export CSV/JSON buttons
  (`file_selector` save dialog, exports the **current filtered view**),
  Clear-all with confirm.

## Capture points

Direct `AuditService` calls (not HookBus: `hookBus` is nullable plugin
infra, its events lack failure reasons, and compliance must not depend on
the plugin system):

| Event | Site | Notes |
|---|---|---|
| `connect` | `SessionProvider._doConnect` | success always; failure only when no retry is scheduled (final failure, `meta.error` + `meta.attempts`) — an unlimited-retry outage must not spam one row per tick |
| `disconnect` | `SessionProvider` drop/close paths | user-closed vs dropped recorded in `meta` |
| `exec` | `SshService.exec` | one site covers bulk run, AI tools, DevOps plugin, JS `ssh.exec`; exit code recorded after completion |
| `input` | `TerminalInputBar._submit` | next to the existing `recordCommand` call; `meta.source = input-bar` |
| `input` | plugin-context `sendInput` | snippets and Dart plugins; `meta.source = snippet` / plugin name |

Wiring in `main.dart`: construct `AuditService`, hand it to
`SshService.audit` and `SessionProvider.audit` (nullable fields, same
pattern as `hookBus`/`recordingStart`), and to the input-bar/plugin-context
via provider lookup. A null `audit` disables capture (tests stay quiet by
default).

## Retention

`SettingsProvider.auditRetentionDays` (default **90**, `0` = keep
forever) with a Settings → Audit section (retention dropdown: 30/90/365/
forever + Clear audit log button). `AuditService.prune()` runs once at
startup after init.

## Error handling

- All writes fail-soft (`debugPrint`, never rethrow) — a broken disk or
  locked DB must not block connects or execs.
- DB open failure at startup → audit disabled for the session; the Audit
  screen shows the open error instead of an empty table.
- Export errors surface as a SnackBar on the Audit screen.

## Testing

- **AuditRedactor:** pure unit tests, one per pattern + no-false-positive
  cases (e.g. `cat password.txt` is untouched).
- **AuditService:** in-memory DB — insert/query round-trip, filter
  combinations, ordering, pagination, prune by age, clearAll, CSV/JSON
  export shape, fail-soft on a closed DB.
- **Capture:** extend `ssh_service` exec tests and the
  `session_provider_template_test`-style fakes to assert events are
  recorded with the right type/source; input bar widget test asserts the
  audit call next to `recordCommand`.
- **Widget:** AuditScreen renders rows, filter narrows results, export
  button calls the service with the active filter.
