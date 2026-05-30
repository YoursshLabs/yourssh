# CSV Host Import — Design Spec

**Date:** 2026-05-30
**Feature:** Phase 1-B — Host import from CSV

---

## Goal

Allow users to import SSH hosts from a CSV file (or pasted CSV text) into YourSSH, with flexible column ordering, sensible defaults for optional fields, and clear warnings for skipped rows.

---

## Section 1: Architecture & CSV Format

### Integration point

Add `parseCsvHosts()` to `app/lib/widgets/import_panel.dart`, alongside the existing `parseSshConfig()` and `parseJsonHosts()`. Update `detectAndParse()` and `_pickFile()` to include CSV.

### Detection heuristic (in `detectAndParse`)

Check in order:
1. JSON → starts with `[` or `{`
2. SSH config → first non-blank line starts with `Host ` (case-insensitive)
3. CSV → first line contains a comma and is not one of the above
4. Fallback → try SSH config parser

### CSV format

| Field | Column name | Required | Default |
|---|---|---|---|
| Host/IP | `host` | **Yes** | — |
| Label | `label` | No | value of `host` |
| Port | `port` | No | `22` |
| Username | `username` | No | `""` |
| Auth type | `auth_type` | No | `password` |
| Group | `group` | No | `""` |
| Tags | `tags` | No | `[]` |

- Header row is **required**; column order is flexible
- `auth_type` accepted values: `password` (default), `key` / `privateKey` → `AuthType.privateKey`, `agent` → `AuthType.agent`
- `tags` is semicolon-separated: `"web;db"` → `['web', 'db']`
- RFC 4180 quoting: values containing commas or newlines must be double-quoted; `""` inside quotes = literal `"`
- `label` falls back to `host` if empty or absent

### File picker update

Accept extensions: `.json`, `.config`, `.conf`, `.txt`, **`.csv``**

### Paste hint text update

Update hint to mention CSV: `"Paste SSH config, JSON, or CSV…"`

---

## Section 2: Error Handling

### File-level errors (abort import)

| Condition | Message |
|---|---|
| Missing `host` column in header | `"CSV missing required 'host' column"` |
| Malformed CSV (odd quotes, parse failure) | `"Could not parse CSV: unexpected format"` |

### Row-level errors (skip row, accumulate warning)

| Condition | Warning |
|---|---|
| `host` cell is empty | `"Row N: missing host, skipped"` |
| `port` non-numeric or out of 1–65535 | `"Row N: invalid port 'X', skipped"` |

- Unknown `auth_type` → silently default to `password` (forgiving)
- Empty rows (all cells blank) → silently skipped, no warning

### Warning display

Warnings accumulate and appear above the preview list:
> "2 rows skipped — tap to see details"

Expandable list shows individual row warnings. Import can still proceed with valid rows.

---

## Section 3: Testing

Unit tests in `test/widgets/import_panel_test.dart` (new group `'parseCsvHosts'`):

| Test | Verifies |
|---|---|
| Basic row | `host`, `label`, `username`, `port` parsed correctly |
| Missing optional fields | defaults: port=22, auth=password, label=host |
| Quoted value with comma | `"New York, NY"` parsed as single field |
| Tags field | `web;db` → `['web', 'db']` |
| `auth_type` variations | `key`→`privateKey`, `password`→`password`, `agent`→`agent` |
| Empty rows | skipped, no crash, no warnings |
| Missing `host` column | returns error, zero hosts |
| Empty `host` cell | row skipped, warning added |
| Invalid port | row skipped, warning added |
| Unknown `auth_type` | defaults to `password`, no error |

---

## Implementation scope

**Files to modify:**
- `app/lib/widgets/import_panel.dart` — add `parseCsvHosts()`, update `detectAndParse()`, `_pickFile()`, hint text, warning UI

**Files to modify (tests):**
- `test/widgets/import_panel_test.dart` — add CSV test group

**No new files needed.** No new packages needed (Dart's `dart:core` `String.split` handles RFC 4180 via a simple hand-rolled parser; no external CSV package required given the simple format).
