# CSV Host Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add CSV import support to the existing import panel so users can import SSH hosts from a `.csv` file or pasted CSV text, with flexible column order, sensible defaults, and per-row warnings for skipped rows.

**Architecture:** Add two top-level functions (`_splitCsvLine` private helper + `parseCsvHosts` public) to `app/lib/widgets/import_panel.dart` alongside the existing `parseSshConfig` and `parseJsonHosts`. Update `detectAndParse`, the file picker, and `_ImportPanelState` to route CSV input through `parseCsvHosts` and surface row-level warnings above the preview list.

**Tech Stack:** Dart 3 records (`({List<Host> hosts, List<String> warnings})`), `dart:core` only (no external CSV package), Flutter `ExpansionTile` for collapsible warnings.

---

## File Map

| File | Change |
|---|---|
| `app/lib/widgets/import_panel.dart` | Add `_splitCsvLine`, `parseCsvHosts`; update `detectAndParse`, `_applyParsed`, `_pickFile`, `_parsePaste`, `_buildFileSection`, `_buildPasteSection`, `build`; add `_csvWarnings` state + `_parseInput` + `_buildWarnings` |
| `app/test/widgets/import_parser_test.dart` | Add `parseCsvHosts` group + `detectAndParse` CSV test |

---

## Task 1: CSV parser (TDD)

**Files:**
- Modify: `app/lib/widgets/import_panel.dart` (add `_splitCsvLine` + `parseCsvHosts` after line 65)
- Modify: `app/test/widgets/import_parser_test.dart` (add `parseCsvHosts` group + `detectAndParse` CSV test)

- [ ] **Step 1: Add failing tests**

Open `app/test/widgets/import_parser_test.dart`. After the closing `}` of the `'detectAndParse'` group and before the final `}` of `main()`, add:

```dart
  group('parseCsvHosts', () {
    test('basic row — parses host, label, username, port', () {
      const csv = 'label,host,port,username\nMy Server,1.2.3.4,2222,deploy';
      final result = parseCsvHosts(csv);
      expect(result.warnings, isEmpty);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, 'My Server');
      expect(result.hosts[0].host, '1.2.3.4');
      expect(result.hosts[0].port, 2222);
      expect(result.hosts[0].username, 'deploy');
    });

    test('missing optional fields — defaults: port=22, auth=password, label=host', () {
      const csv = 'host\n10.0.0.1';
      final result = parseCsvHosts(csv);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].label, '10.0.0.1');
      expect(result.hosts[0].port, 22);
      expect(result.hosts[0].authType, AuthType.password);
      expect(result.hosts[0].username, '');
      expect(result.hosts[0].group, '');
      expect(result.hosts[0].tags, isEmpty);
    });

    test('quoted value with comma inside', () {
      const csv = 'label,host\n"New York, NY",nyc.example.com';
      final result = parseCsvHosts(csv);
      expect(result.hosts[0].label, 'New York, NY');
    });

    test('tags parsed as semicolon-separated list', () {
      const csv = 'host,tags\nserver.com,web;db';
      final result = parseCsvHosts(csv);
      expect(result.hosts[0].tags, ['web', 'db']);
    });

    test('auth_type: key→privateKey, agent→agent, password→password, unknown→password', () {
      const csv = 'host,auth_type\na.com,key\nb.com,agent\nc.com,password\nd.com,kerberos';
      final result = parseCsvHosts(csv);
      expect(result.hosts[0].authType, AuthType.privateKey);
      expect(result.hosts[1].authType, AuthType.agent);
      expect(result.hosts[2].authType, AuthType.password);
      expect(result.hosts[3].authType, AuthType.password);
    });

    test('empty rows are silently skipped — no warnings', () {
      const csv = 'host\n1.2.3.4\n\n5.6.7.8';
      final result = parseCsvHosts(csv);
      expect(result.hosts.length, 2);
      expect(result.warnings, isEmpty);
    });

    test('missing host column — throws FormatException', () {
      const csv = 'label,port\nMy Server,22';
      expect(() => parseCsvHosts(csv), throwsA(isA<FormatException>()));
    });

    test('empty host cell — row skipped with warning', () {
      const csv = 'host,label\n,Empty Host';
      final result = parseCsvHosts(csv);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains('missing host'));
    });

    test('invalid port — row skipped with warning', () {
      const csv = 'host,port\nserver.com,99999';
      final result = parseCsvHosts(csv);
      expect(result.hosts, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings[0], contains("invalid port '99999'"));
    });

    test('unknown auth_type defaults to password — no warning', () {
      const csv = 'host,auth_type\nserver.com,kerberos';
      final result = parseCsvHosts(csv);
      expect(result.hosts.length, 1);
      expect(result.hosts[0].authType, AuthType.password);
      expect(result.warnings, isEmpty);
    });
  });
```

Also add one test inside the existing `'detectAndParse'` group (after the last `test(...)` inside that group, before its closing `}`):

```dart
    test('detects CSV when first line contains commas', () {
      const csv = 'host,label\nserver.com,My Server';
      final result = detectAndParse(csv);
      expect(result.length, 1);
      expect(result[0].host, 'server.com');
    });
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd app && flutter test test/widgets/import_parser_test.dart --no-pub
```

Expected: failures on `parseCsvHosts` group and `detectAndParse` CSV test (functions not defined yet).

- [ ] **Step 3: Add `_splitCsvLine` and `parseCsvHosts` to `import_panel.dart`**

In `app/lib/widgets/import_panel.dart`, add the following block **after** the closing `}` of `parseJsonHosts` (after line 65) and **before** the `detectAndParse` function:

```dart
List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        sb.write('"');
        i += 2;
      } else {
        inQuotes = !inQuotes;
        i++;
      }
    } else if (ch == ',' && !inQuotes) {
      fields.add(sb.toString());
      sb.clear();
      i++;
    } else {
      sb.write(ch);
      i++;
    }
  }
  if (inQuotes) throw FormatException('Unterminated quote in CSV');
  fields.add(sb.toString());
  return fields;
}

({List<Host> hosts, List<String> warnings}) parseCsvHosts(String input) {
  final lines = input.split('\n').map((l) => l.trimRight()).toList();
  while (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  if (lines.isEmpty) return (hosts: [], warnings: []);

  final header = _splitCsvLine(lines[0]).map((h) => h.trim().toLowerCase()).toList();
  if (!header.contains('host')) {
    throw FormatException("CSV missing required 'host' column");
  }

  int idx(String name) => header.indexOf(name);
  final hostIdx = idx('host');
  final labelIdx = idx('label');
  final portIdx = idx('port');
  final userIdx = idx('username');
  final authIdx = idx('auth_type');
  final groupIdx = idx('group');
  final tagsIdx = idx('tags');

  final hosts = <Host>[];
  final warnings = <String>[];

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    List<String> cells;
    try {
      cells = _splitCsvLine(line);
    } catch (_) {
      warnings.add('Row ${i + 1}: malformed CSV, skipped');
      continue;
    }

    String cell(int colIdx) =>
        colIdx >= 0 && colIdx < cells.length ? cells[colIdx].trim() : '';

    final hostVal = cell(hostIdx);
    if (hostVal.isEmpty) {
      warnings.add('Row ${i + 1}: missing host, skipped');
      continue;
    }

    int port = 22;
    final portStr = cell(portIdx);
    if (portStr.isNotEmpty) {
      final parsed = int.tryParse(portStr);
      if (parsed == null || parsed < 1 || parsed > 65535) {
        warnings.add("Row ${i + 1}: invalid port '$portStr', skipped");
        continue;
      }
      port = parsed;
    }

    final labelVal = cell(labelIdx);
    final authVal = cell(authIdx).toLowerCase();
    final tagsVal = cell(tagsIdx);

    final authType = switch (authVal) {
      'key' || 'privatekey' => AuthType.privateKey,
      'agent' => AuthType.agent,
      _ => AuthType.password,
    };

    final tags = tagsVal.isEmpty
        ? <String>[]
        : tagsVal.split(';').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

    hosts.add(Host(
      label: labelVal.isEmpty ? hostVal : labelVal,
      host: hostVal,
      port: port,
      username: cell(userIdx),
      authType: authType,
      group: cell(groupIdx),
      tags: tags,
    ));
  }

  return (hosts: hosts, warnings: warnings);
}
```

- [ ] **Step 4: Update `detectAndParse` to detect CSV**

Replace the existing `detectAndParse` function (lines 67–72 in the original file):

```dart
List<Host> detectAndParse(String input) {
  final trimmed = input.trimLeft();
  if (trimmed.toLowerCase().startsWith('host ')) return parseSshConfig(input);
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) return parseJsonHosts(input);
  final firstLine = trimmed.split('\n').first;
  if (firstLine.contains(',')) {
    try {
      return parseCsvHosts(input).hosts;
    } on FormatException {
      return [];
    }
  }
  return [];
}
```

- [ ] **Step 5: Run tests — expect all pass**

```bash
cd app && flutter test test/widgets/import_parser_test.dart --no-pub
```

Expected: all tests pass including the new `parseCsvHosts` group and `detectAndParse` CSV test.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/import_panel.dart app/test/widgets/import_parser_test.dart
git commit -m "feat: add CSV host parser with RFC 4180 quoting and row-level warnings"
```

---

## Task 2: UI integration

**Files:**
- Modify: `app/lib/widgets/import_panel.dart` (state, `_applyParsed`, `_pickFile`, `_parsePaste`, `_buildFileSection`, `_buildPasteSection`, `build`)

- [ ] **Step 1: Add `_csvWarnings` state field**

In `_ImportPanelState`, add `_csvWarnings` after `_overwrite`:

```dart
  final Map<int, bool> _included = {};
  final Map<int, bool> _overwrite = {};
  List<String> _csvWarnings = [];
```

- [ ] **Step 2: Update `_applyParsed` signature to accept warnings**

Replace the existing `_applyParsed` method:

```dart
  void _applyParsed(List<Host> hosts, {List<String> warnings = const []}) {
    setState(() {
      _parsed = hosts;
      _csvWarnings = List.of(warnings);
      _parseError = hosts.isEmpty && warnings.isEmpty
          ? 'No hosts found or unrecognized format'
          : null;
      _included.clear();
      _overwrite.clear();
      for (var i = 0; i < hosts.length; i++) {
        _included[i] = true;
        _overwrite[i] = false;
      }
    });
  }
```

- [ ] **Step 3: Add `_parseInput` method, update `_pickFile` + `_parsePaste`, and reset warnings on tab switch**

Add `_parseInput` method to `_ImportPanelState`:

```dart
  void _parseInput(String input) {
    final trimmed = input.trimLeft();
    final firstLine = trimmed.split('\n').first;
    final looksLikeCsv = firstLine.contains(',') &&
        !trimmed.toLowerCase().startsWith('host ') &&
        !trimmed.startsWith('[') &&
        !trimmed.startsWith('{');

    if (looksLikeCsv) {
      try {
        final result = parseCsvHosts(input);
        _applyParsed(result.hosts, warnings: result.warnings);
      } on FormatException catch (e) {
        setState(() {
          _csvWarnings = [];
          _parsed = [];
          _parseError = e.message;
          _included.clear();
          _overwrite.clear();
        });
      }
    } else {
      _applyParsed(detectAndParse(input));
    }
  }
```

Replace the existing `_pickFile` method:

```dart
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'config', 'conf', 'txt', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    _parseInput(utf8.decode(bytes));
  }
```

Replace the existing `_parsePaste` one-liner:

```dart
  void _parsePaste() => _parseInput(_pasteCtrl.text);
```

Also update `_modeTab` to reset `_csvWarnings` when switching tabs. In `_modeTab`, the `setState` block currently sets `_mode`, `_parsed`, and `_parseError`. Add `_csvWarnings = [];` to that block:

```dart
        onTap: () => setState(() {
          _mode = mode;
          _parsed = [];
          _parseError = null;
          _csvWarnings = [];
        }),
```

- [ ] **Step 4: Update file section label and paste hint text**

In `_buildFileSection`, replace the `Text` widget label:

```dart
// Old:
Text('Choose .json or config file', ...)
// New:
Text('Choose file (.json, .csv, .config)', ...)
```

In `_buildPasteSection`, replace the `hintText`:

```dart
// Old:
hintText: 'Paste .ssh/config or JSON here...',
// New:
hintText: 'Paste SSH config, JSON, or CSV...',
```

- [ ] **Step 5: Add `_buildWarnings` method**

Add to `_ImportPanelState`:

```dart
  Widget _buildWarnings() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          '${_csvWarnings.length} row${_csvWarnings.length == 1 ? '' : 's'} skipped — tap to see details',
          style: const TextStyle(color: Colors.orange, fontSize: 11),
        ),
        children: _csvWarnings
            .map((w) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(w,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ))
            .toList(),
      ),
    );
  }
```

- [ ] **Step 6: Render warnings in `build`**

In the `build` method, in the `ListView` children, add the warnings block after the `_parseError` block and before the `_parsed.isNotEmpty` block:

```dart
                if (_parseError != null) ...[
                  const SizedBox(height: 8),
                  Text(_parseError!, style: const TextStyle(color: AppColors.red, fontSize: 11)),
                ],
                if (_csvWarnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildWarnings(),
                ],
                if (_parsed.isNotEmpty) ...[
```

- [ ] **Step 7: Run full test suite**

```bash
cd app && flutter test --no-pub
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/lib/widgets/import_panel.dart
git commit -m "feat: wire CSV import into import panel UI with warnings display"
```
