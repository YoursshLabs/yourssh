# Import Sources Expansion — Design Spec

**Date:** 2026-06-08  
**Status:** Approved

## Overview

Expand the Import Hosts panel from a format-agnostic file/paste picker into a source-aware flow with 9 named import sources, a grid source-picker UI, and dedicated parsers for each format.

## Scope

**In scope:**
- Source-picker grid UI (9 sources)
- Parser extraction into `app/lib/util/import_parsers.dart`
- New parsers: PuTTY (.reg), MobaXterm (.mxtsessions), SecureCRT (XML), Ansible (INI), WinSCP (.ini), Termius (JSON), SSH URI
- Existing parsers migrated to the new abstraction: SSH config, CSV
- Per-source file extension hints and help text

**Out of scope:**
- Ansible YAML inventory (deferred — complexity disproportionate to benefit)
- Vendor logo SVG assets (use Material icons)
- Cloud-based import (AWS, Tailscale, etc.)

---

## 1. Parser Architecture

### File
`app/lib/util/import_parsers.dart`

### Types

```dart
typedef ParseResult = ({List<Host> hosts, List<String> warnings});

abstract class ImportParser {
  ParseResult parse(String input);
}
```

All parsers return `ParseResult`. Single-host parse errors are collected in `warnings` and skipped; structural errors (unrecognised format) return `hosts: [], warnings: ['<reason>']`.

### Source registry

```dart
enum ImportSource {
  sshConfig, csv, putty, mobaXterm, secureCrt,
  ansible, winScp, termius, sshUri,
}

class ImportSourceDef {
  final ImportSource source;
  final String label;
  final IconData icon;
  final Color iconColor;
  final List<String> fileExtensions;   // passed to FilePicker allowedExtensions
  final String hint;                   // shown below file/paste area
  final ImportParser parser;
}
```

`ImportSourceDef.all` — ordered list of all 9 definitions (order = grid display order).

---

## 2. UI Flow

```
ImportPanel
  ├── [Step: sourcePicker]  _selectedSource == null
  │     └── 3-column grid of ImportSourceCard
  └── [Step: input + preview]  _selectedSource != null
        ├── Header: "← Import from <Label>"  (back resets _selectedSource)
        ├── From file / Paste text tab toggle  (unchanged)
        ├── Hint text from ImportSourceDef.hint
        ├── File picker filtered to ImportSourceDef.fileExtensions
        ├── Parse error / warnings  (unchanged)
        └── Preview + Import button  (unchanged)
```

State: `ImportSource? _selectedSource` — `null` shows picker, set shows input/preview.

Panel header:
- Picker step: `"Import Hosts"` (no back arrow)
- Input step: `"Import from PuTTY"` + `←` icon button that resets `_selectedSource`

---

## 3. Source Cards

3-column `GridView` with fixed `crossAxisCount: 3`, `childAspectRatio: 1.0`.  
Card: icon (28px) centered, label below (10px, textSecondary), rounded corners, border.  
Hover/tap: slight background highlight (`AppColors.textPrimary.withValues(alpha: 0.06)`).

| Source | Label | Icon | Color |
|--------|-------|------|-------|
| sshConfig | ~/.ssh | `Icons.terminal` | blue |
| csv | CSV | `Icons.table_chart` | green |
| putty | PuTTY | `Icons.computer` | amber |
| mobaXterm | MobaXterm | `Icons.grid_view` | purple |
| secureCrt | SecureCRT | `Icons.lock` | orange |
| ansible | Ansible | `Icons.settings_suggest` | red |
| winScp | WinSCP | `Icons.swap_horiz` | teal |
| termius | Termius | `Icons.phonelink` | indigo |
| sshUri | SSH URI | `Icons.link` | cyan |

---

## 4. Parser Specs

### 4.1 SshConfigParser (migrated from `parseSshConfig`)
No changes to logic. Wraps existing function in `ParseResult`.

### 4.2 CsvParser (migrated from `parseCsvHosts`)
No changes to logic. Wraps existing function in `ParseResult`.

### 4.3 PuttyRegParser
**Input:** Windows Registry `.reg` export (UTF-8 or UTF-16 LE with BOM).

**Format:**
```
[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\SessionName]
"HostName"="192.168.1.1"
"PortNumber"=dword:00000016
"UserName"="root"
```

**Logic:**
1. Strip UTF-16 BOM if present (`\xFF\xFE` → re-decode as UTF-16 LE).
2. Regex for section headers: `^\[HKEY_.*\\Sessions\\([^\]]+)\]$` — capture session name (URL-decode `%20` → space).
3. Within each session block, extract `HostName`, `PortNumber` (hex dword → `int.parse(hex, radix: 16)`), `UserName`.
4. Skip sessions where `HostName` is empty.
5. Warnings for sessions missing `HostName`.

**File extensions:** `reg`, `txt`

### 4.4 MobaXtermParser
**Input:** `.mxtsessions` INI-like file.

**Format:**
```
[Bookmarks]
SSH server1 (root) = 0  192.168.1.1  22  root  ...
```

**Logic:**
1. Split lines; skip `[Bookmarks*]` section headers and blank lines.
2. For each line containing `=`: split on first `=` → `(labelPart, valuePart)`.
3. Tokenise `valuePart` by whitespace (collapse runs). Index 0 = type, 1 = host, 2 = port, 3 = user.
4. Skip if type ≠ `"0"` (only SSH sessions; type 4 = Telnet, etc.).
5. Skip if host empty. Warn on malformed rows.

**File extensions:** `mxtsessions`, `txt`

### 4.5 SecureCrtParser
**Input:** SecureCRT XML session export.

**Format:**
```xml
<VanDyke>
  <key name="Sessions">
    <key name="FolderName">
      <key name="SessionName">
        <value name="Hostname" type="string">192.168.1.1</value>
        <value name="Port" type="dword">22</value>
        <value name="Username" type="string">admin</value>
      </key>
    </key>
  </key>
</VanDyke>
```

**Logic:**
1. Parse with `xml` package (already in pubspec at `^6.5.0`).
2. Find root `<key name="Sessions">`.
3. Recursively walk `<key>` descendants (depth-first); a key is a session if it has a `<value name="Hostname">` child.
4. Session label = key's `name` attribute; folder hierarchy above → joined with `/` → `Host.group`.
5. Port defaults to 22 if absent or unparseable.
6. Skip sessions with empty hostname.

**File extensions:** `xml`, `txt`

### 4.6 AnsibleParser
**Input:** Ansible INI inventory (YAML deferred).

**Format:**
```ini
[webservers]
web1.example.com
web2.example.com ansible_user=deploy ansible_port=2222 ansible_host=10.0.0.1

[databases:vars]
ansible_user=postgres
```

**Logic:**
1. Track current group name (text inside `[...]`, strip `:vars`, `:children` suffixes).
2. Skip `[*:vars]` and `[*:children]` sections entirely.
3. For each non-blank, non-comment (`#`) data line:
   - Split on whitespace: first token = alias/hostname, remaining = `key=value` vars.
   - Collect vars: `ansible_host`, `ansible_user`, `ansible_port`, `ansible_ssh_user` (alias).
   - `host` = `ansible_host` if present, else first token.
   - `username` = `ansible_user` ?? `ansible_ssh_user` ?? `'root'`.
   - `port` = `ansible_port` parsed as int, default 22.
   - `label` = first token (alias).
   - `group` = current group name.
4. Warn on invalid port values.

**File extensions:** `yml`, `yaml`, `ini`, `txt`

### 4.7 WinScpParser
**Input:** WinSCP `.ini` session file.

**Format:**
```ini
[Sessions\MyServer]
HostName=192.168.1.1
PortNumber=22
UserName=admin
```

**Logic:**
1. Regex for section header: `^\[Sessions\\(.+)\]$` — capture session path (URL-decode `%20`).
2. Skip `[Sessions\]` root section (no hostname possible).
3. Within each session block, extract `HostName`, `PortNumber`, `UserName`.
4. Session label = last component of path (`path.split('\\').last`); parent components → `Host.group`.
5. Skip sessions with empty `HostName`.

**File extensions:** `ini`, `txt`

### 4.8 TermiusParser
**Input:** Termius JSON export (`.termius` file).

**Format:**
```json
{
  "hosts": [
    {
      "label": "My Server",
      "address": "192.168.1.1",
      "port": 22,
      "username": "admin",
      "group": {"label": "Production"}
    }
  ]
}
```

**Logic:**
1. `jsonDecode` input.
2. If result has `"hosts"` key → parse as Termius format: map `address` → `host`, `group.label` → `Host.group`.
3. Fallback: if no `"hosts"` key → delegate to existing `CsvParser`/`SshConfigParser` detection (i.e. re-use `detectAndParse`). This handles users who paste raw JSON from an earlier YourSSH export via this source.
4. Skip entries with empty `address`.

**File extensions:** `termius`, `json`, `txt`

### 4.9 SshUriParser
**Input:** Plain text, one URI per line.

**Format:**
```
ssh://admin@192.168.1.1:2222
ssh://root@10.0.0.1
```

**Logic:**
1. Split by newlines; trim each line.
2. Regex per line: `ssh://([^@]+)@([^:/?#\s]+)(?::(\d+))?(?:[/?#].*)?$`
3. Groups: (1) username, (2) host, (3) port (optional, default 22).
4. Label = `user@host`.
5. Skip non-matching lines silently (no warning — mixed-content paste is common).

**File extensions:** `txt`

---

## 5. Backward Compatibility

- `parseSshConfig`, `parseCsvHosts`, `detectAndParse` remain exported from `import_panel.dart` (called through to new parser classes) — existing tests pass without changes.
- `_pickFile` in `_ImportPanelState` uses source-specific extensions when a source is selected, falls back to current list `['json', 'config', 'conf', 'txt', 'csv']` when none (unreachable in new flow but safe).

---

## 6. Testing

All parsers in `app/test/services/import_parsers_test.dart`:
- Happy path per parser
- Empty input → `hosts: [], warnings: []`
- Malformed input → warnings, no crash
- Duplicate host detection (handled by `ImportPanel`, not parsers)

Existing `app/test/widgets/import_parser_test.dart` continues to pass (backward-compat wrappers).

---

## 7. Files Changed

| File | Change |
|------|--------|
| `app/lib/util/import_parsers.dart` | **new** — all parsers + `ImportSourceDef` registry |
| `app/lib/widgets/import_panel.dart` | refactor — source-picker UI, delegate to new parsers |
| `app/test/services/import_parsers_test.dart` | **new** — parser unit tests |
