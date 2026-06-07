# Internal Audit Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local SQLite audit trail of connects/disconnects and commands (exec + input-bar + plugin sendInput), with secret redaction, a filterable viewer screen, CSV/JSON export, and retention pruning.

**Architecture:** A fail-soft `AuditService` (sqlite3, single table, WAL) is injected into `SshService` (exec events, with `auditSource` threaded from callers), `SessionProvider` (connect/disconnect), the terminal input bar, and the plugin context. A pure `AuditRedactor` masks secrets before insert. `AuditProvider` + `AuditScreen` (new `NavSection.audit`) give filters/search/export.

**Tech Stack:** `sqlite3` + `sqlite3_flutter_libs` (new deps, no codegen), `path_provider` (existing), `file_selector` (existing) for export save.

**Spec:** `docs/superpowers/specs/2026-06-06-internal-audit-log-design.md`

---

## File map

| File | Change |
|---|---|
| `app/pubspec.yaml` | add `sqlite3`, `sqlite3_flutter_libs` |
| `app/lib/services/audit_redactor.dart` | **new** — pure secret masking |
| `app/lib/models/audit_event.dart` | **new** — row model + CSV/JSON |
| `app/lib/services/audit_service.dart` | **new** — DB, record/query/prune/clear/export, `AuditFilter` |
| `app/lib/services/ssh_service.dart` | `audit` field; exec records events; `auditSource` param |
| exec callers (bulk dialog, main.dart JS adapter, plugin context, devops services, network stats) | thread `auditSource` |
| `app/lib/providers/session_provider.dart` | `audit` field; connect/disconnect events |
| `app/lib/widgets/terminal_input_bar.dart` | audit input-bar submissions |
| `app/lib/plugins/plugin_context_impl.dart` | audit `sendInput` |
| `app/lib/providers/settings_provider.dart` | `auditRetentionDays` (default 90) |
| `app/lib/widgets/settings_screen.dart` | Audit section (retention + clear) |
| `app/lib/providers/audit_provider.dart` | **new** — filter state + paging |
| `app/lib/widgets/audit_screen.dart` | **new** — viewer + export |
| `app/lib/screens/main_screen.dart` | `NavSection.audit` + nav item + content |
| `app/lib/main.dart` | construct/init/inject AuditService + AuditProvider; prune at startup |
| `CLAUDE.md` | document the feature |

Notes locked in during exploration:
- `NetworkStatsService` polls `cat /proc/net/dev` on a timer → `auditSource: null` means **skip auditing** (signature `String? auditSource = 'app'`). If `SshService.detectOs` routes through `exec`, give it `auditSource: null` too (one-shot but still noise).
- `psql -p` is the **port** flag, not password — drop psql from the `-p` redaction pattern; `PGPASSWORD=` is caught by the key=value pattern (which allows prefixes like `PG`).
- Disconnect events: `closeSession` (user-closed) + the two `onSessionDropped` sites in `SessionProvider` (lines ~169 graceful, ~185 error). Connect failure logs **only** when no retry is scheduled.
- sqlite3 tests use `sqlite3.openInMemory()` — works under `flutter test` on macOS via the system dylib. CI on Linux needs `libsqlite3` present (standard on ubuntu images).

All commands run from `app/`: `cd app`.

---

### Task 1: AuditRedactor (pure)

**Files:**
- Create: `app/lib/services/audit_redactor.dart`
- Test: `app/test/services/audit_redactor_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/audit_redactor.dart';

void main() {
  String r(String s) => AuditRedactor.redact(s);

  test('key=value secrets are masked, key kept', () {
    expect(r('mysql -u root password=hunter2'),
        'mysql -u root password=[REDACTED]');
    expect(r('export API_KEY=abc123'), 'export API_KEY=[REDACTED]');
    expect(r('TOKEN=t SECRET=s'), 'TOKEN=[REDACTED] SECRET=[REDACTED]');
    expect(r('PGPASSWORD=pg psql -h db'), 'PGPASSWORD=[REDACTED] psql -h db');
    expect(r('curl -d passwd=x'), 'curl -d passwd=[REDACTED]');
  });

  test('Authorization: Bearer is masked', () {
    expect(r("curl -H 'Authorization: Bearer eyJabc'"),
        "curl -H 'Authorization: Bearer [REDACTED]'");
  });

  test('sshpass -p is masked', () {
    expect(r('sshpass -p s3cret ssh u@h'), 'sshpass -p [REDACTED] ssh u@h');
  });

  test('mysql/mariadb attached -p is masked', () {
    expect(r('mysql -u root -ps3cret db'), 'mysql -u root -p[REDACTED] db');
    expect(r('mariadb -psecret'), 'mariadb -p[REDACTED]');
  });

  test('psql -p stays untouched (port, not password)', () {
    expect(r('psql -p 5432 -h db'), 'psql -p 5432 -h db');
  });

  test('URL userinfo password is masked', () {
    expect(r('curl https://user:pw@example.com/x'),
        'curl https://user:[REDACTED]@example.com/x');
  });

  test('no false positives', () {
    expect(r('cat password.txt'), 'cat password.txt');
    expect(r('ls -la /srv'), 'ls -la /srv');
    expect(r('echo token bucket'), 'echo token bucket');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/audit_redactor_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `app/lib/services/audit_redactor.dart`:

```dart
/// Pure secret masking for audit-log commands. Patterns mask only the
/// secret portion ([kMask]) so the command stays readable. No IO.
class AuditRedactor {
  static const kMask = '[REDACTED]';

  // key=value style: password=, passwd=, token=, secret=, api_key=,
  // apikey=, and prefixed forms (PGPASSWORD=, GITHUB_TOKEN=, …).
  static final _kv = RegExp(
      r'([\w-]*(?:password|passwd|token|secret|api[_-]?key)\s*=\s*)(\S+)',
      caseSensitive: false);
  static final _bearer = RegExp(
      r'(authorization:\s*bearer\s+)([^\s' "'" r'"]+)',
      caseSensitive: false);
  static final _sshpass =
      RegExp(r'(\bsshpass\s+-p\s+)(\S+)', caseSensitive: false);
  // mysql/mariadb attached password (-psecret). psql's -p is the port —
  // excluded; PGPASSWORD= is caught by _kv.
  static final _mysqlP = RegExp(r'(\b(?:mysql|mariadb)\b[^\n]*?\s-p)(\S+)');
  static final _urlCred = RegExp(r'(\w+://[^/\s:@]+:)([^@\s]+)(?=@)');

  static String redact(String command) {
    var out = command;
    out = out.replaceAllMapped(_kv, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_bearer, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_sshpass, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_mysqlP, (m) => '${m[1]}$kMask');
    out = out.replaceAllMapped(_urlCred, (m) => '${m[1]}$kMask');
    return out;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/audit_redactor_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/audit_redactor.dart app/test/services/audit_redactor_test.dart
git commit -m "feat: audit-log secret redactor"
```

---

### Task 2: AuditEvent model

**Files:**
- Create: `app/lib/models/audit_event.dart`
- Test: `app/test/models/audit_event_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/models/host.dart';

void main() {
  test('AuditEvent.now fills host denormalized fields', () {
    final h = Host(label: 'prod', host: 'p.com', username: 'root');
    final e = AuditEvent.now(
        type: AuditEventType.exec,
        host: h,
        sessionId: 's1',
        command: 'ls',
        exitCode: 0,
        meta: const {'source': 'bulk'});
    expect(e.hostId, h.id);
    expect(e.hostLabel, 'prod');
    expect(e.username, 'root');
    expect(e.type, AuditEventType.exec);
  });

  test('fromRow round-trips through a row map', () {
    final e = AuditEvent.fromRow({
      'id': 7,
      'ts': DateTime.utc(2026, 6, 6).millisecondsSinceEpoch,
      'type': 'connect',
      'host_id': 'h1',
      'host_label': 'prod',
      'username': 'root',
      'session_id': 's1',
      'command': null,
      'exit_code': null,
      'meta': '{"error":"timeout"}',
    });
    expect(e.id, 7);
    expect(e.type, AuditEventType.connect);
    expect(e.meta, {'error': 'timeout'});
    expect(e.command, isNull);
  });

  test('toCsvRow shape and toJson keys', () {
    final e = AuditEvent.now(type: AuditEventType.input, command: 'htop');
    expect(e.toCsvRow().length, 8);
    expect(e.toJson().keys,
        containsAll(['ts', 'type', 'command', 'meta', 'hostLabel']));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/audit_event_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `app/lib/models/audit_event.dart`:

```dart
import 'dart:convert';

import 'host.dart';

enum AuditEventType { connect, disconnect, exec, input }

/// One immutable audit-log row. Host fields are denormalized at record
/// time — the host may be renamed or deleted later.
class AuditEvent {
  final int? id;
  final DateTime ts;
  final AuditEventType type;
  final String? hostId;
  final String? hostLabel;
  final String? username;
  final String? sessionId;
  final String? command;
  final int? exitCode;
  final Map<String, dynamic> meta;

  const AuditEvent({
    this.id,
    required this.ts,
    required this.type,
    this.hostId,
    this.hostLabel,
    this.username,
    this.sessionId,
    this.command,
    this.exitCode,
    this.meta = const {},
  });

  AuditEvent.now({
    required this.type,
    Host? host,
    this.sessionId,
    this.command,
    this.exitCode,
    this.meta = const {},
  })  : id = null,
        ts = DateTime.now(),
        hostId = host?.id,
        hostLabel = host?.label,
        username = host?.username;

  factory AuditEvent.fromRow(Map<String, dynamic> r) => AuditEvent(
        id: r['id'] as int?,
        ts: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
        type: AuditEventType.values.byName(r['type'] as String),
        hostId: r['host_id'] as String?,
        hostLabel: r['host_label'] as String?,
        username: r['username'] as String?,
        sessionId: r['session_id'] as String?,
        command: r['command'] as String?,
        exitCode: r['exit_code'] as int?,
        meta: r['meta'] == null
            ? const {}
            : (jsonDecode(r['meta'] as String) as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'ts': ts.toIso8601String(),
        'type': type.name,
        'hostId': hostId,
        'hostLabel': hostLabel,
        'username': username,
        'sessionId': sessionId,
        'command': command,
        'exitCode': exitCode,
        'meta': meta,
      };

  List<String> toCsvRow() => [
        ts.toIso8601String(),
        type.name,
        hostLabel ?? '',
        username ?? '',
        sessionId ?? '',
        command ?? '',
        exitCode?.toString() ?? '',
        meta.isEmpty ? '' : jsonEncode(meta),
      ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/audit_event_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/audit_event.dart app/test/models/audit_event_test.dart
git commit -m "feat: AuditEvent model"
```

---

### Task 3: AuditService + sqlite3 dependency

**Files:**
- Modify: `app/pubspec.yaml` (dependencies)
- Create: `app/lib/services/audit_service.dart`
- Test: `app/test/services/audit_service_test.dart` (new)

- [ ] **Step 1: Add dependencies**

In `app/pubspec.yaml` under `dependencies:` (after the `convert:` entry):

```yaml
  # Audit log storage (direct SQL, no codegen)
  sqlite3: ^2.4.0
  # Bundles the native sqlite3 library on macOS/Windows/Linux
  sqlite3_flutter_libs: ^0.5.20
```

Run: `cd app && flutter pub get`
Expected: resolves cleanly.

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/services/audit_service.dart';

void main() {
  late AuditService svc;

  setUp(() {
    svc = AuditService()..initInMemory();
  });

  tearDown(() => svc.dispose());

  AuditEvent ev(AuditEventType t,
          {String? hostId, String? cmd, int? code, DateTime? ts}) =>
      AuditEvent(
          ts: ts ?? DateTime.now(),
          type: t,
          hostId: hostId,
          hostLabel: hostId,
          command: cmd,
          exitCode: code);

  test('insert/query round-trip, newest first', () {
    svc.record(ev(AuditEventType.connect,
        hostId: 'h1', ts: DateTime(2026, 1, 1)));
    svc.record(ev(AuditEventType.exec,
        hostId: 'h1', cmd: 'ls', code: 0, ts: DateTime(2026, 1, 2)));
    final rows = svc.query(const AuditFilter());
    expect(rows.length, 2);
    expect(rows.first.type, AuditEventType.exec); // newest first
    expect(rows.first.command, 'ls');
    expect(rows.first.exitCode, 0);
  });

  test('commands are redacted before insert', () {
    svc.record(ev(AuditEventType.exec, cmd: 'export TOKEN=abc'));
    expect(svc.query(const AuditFilter()).single.command,
        'export TOKEN=[REDACTED]');
  });

  test('filters: host, type, time range, search', () {
    svc.record(ev(AuditEventType.exec,
        hostId: 'h1', cmd: 'docker ps', ts: DateTime(2026, 1, 1)));
    svc.record(ev(AuditEventType.exec,
        hostId: 'h2', cmd: 'uptime', ts: DateTime(2026, 2, 1)));
    svc.record(ev(AuditEventType.connect,
        hostId: 'h2', ts: DateTime(2026, 2, 2)));

    expect(svc.query(const AuditFilter(hostId: 'h1')).length, 1);
    expect(svc.query(const AuditFilter(type: 'exec')).length, 2);
    expect(
        svc
            .query(AuditFilter(
                fromTs: DateTime(2026, 1, 15).millisecondsSinceEpoch))
            .length,
        2);
    expect(svc.query(const AuditFilter(search: 'docker')).length, 1);
  });

  test('pagination via limit/offset', () {
    for (var i = 0; i < 5; i++) {
      svc.record(ev(AuditEventType.exec, cmd: 'c$i'));
    }
    expect(svc.query(const AuditFilter(), limit: 2).length, 2);
    expect(svc.query(const AuditFilter(), limit: 2, offset: 4).length, 1);
  });

  test('prune deletes only rows older than retention', () {
    svc.record(ev(AuditEventType.exec,
        cmd: 'old', ts: DateTime.now().subtract(const Duration(days: 100))));
    svc.record(ev(AuditEventType.exec, cmd: 'new'));
    svc.prune(90);
    expect(svc.query(const AuditFilter()).single.command, 'new');
    svc.prune(0); // 0 = keep forever → no-op
    expect(svc.query(const AuditFilter()).length, 1);
  });

  test('clearAll empties the table', () {
    svc.record(ev(AuditEventType.exec, cmd: 'x'));
    svc.clearAll();
    expect(svc.query(const AuditFilter()), isEmpty);
  });

  test('export CSV has header + rows; JSON is a list', () {
    svc.record(ev(AuditEventType.exec, hostId: 'h1', cmd: 'ls', code: 0));
    final csv = svc.exportCsv(const AuditFilter());
    expect(csv.split('\n').first,
        'ts,type,host_label,username,session_id,command,exit_code,meta');
    expect(csv.split('\n').length, 2);
    expect(svc.exportJson(const AuditFilter()), startsWith('['));
  });

  test('CSV escapes quotes and commas', () {
    svc.record(ev(AuditEventType.exec, cmd: 'echo "a,b"'));
    final dataLine = svc.exportCsv(const AuditFilter()).split('\n')[1];
    expect(dataLine, contains('"echo ""a,b"""'));
  });

  test('record/query are fail-soft after dispose', () {
    svc.dispose();
    expect(() => svc.record(ev(AuditEventType.exec, cmd: 'x')),
        returnsNormally);
    expect(svc.query(const AuditFilter()), isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/services/audit_service_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 4: Implement**

Create `app/lib/services/audit_service.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/audit_event.dart';
import 'audit_redactor.dart';

/// Query filter; null fields mean "no constraint".
class AuditFilter {
  final String? hostId;
  final String? type;
  final int? fromTs;
  final int? toTs;
  final String? search;
  const AuditFilter(
      {this.hostId, this.type, this.fromTs, this.toTs, this.search});

  (String, List<Object?>) toWhere() {
    final clauses = <String>[];
    final args = <Object?>[];
    if (hostId != null) {
      clauses.add('host_id = ?');
      args.add(hostId);
    }
    if (type != null) {
      clauses.add('type = ?');
      args.add(type);
    }
    if (fromTs != null) {
      clauses.add('ts >= ?');
      args.add(fromTs);
    }
    if (toTs != null) {
      clauses.add('ts <= ?');
      args.add(toTs);
    }
    final s = search?.trim();
    if (s != null && s.isNotEmpty) {
      clauses.add('(command LIKE ? OR host_label LIKE ?)');
      args
        ..add('%$s%')
        ..add('%$s%');
    }
    return (clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}', args);
  }
}

/// Append-only audit trail in a local SQLite DB. Every write is fail-soft:
/// auditing must never break an SSH operation, so errors are logged and
/// swallowed. See docs/superpowers/specs/2026-06-06-internal-audit-log-design.md.
class AuditService {
  Database? _db;
  String? initError;
  bool get isAvailable => _db != null;

  static const _schema = '''
CREATE TABLE IF NOT EXISTS audit_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  type TEXT NOT NULL,
  host_id TEXT,
  host_label TEXT,
  username TEXT,
  session_id TEXT,
  command TEXT,
  exit_code INTEGER,
  meta TEXT
)''';

  /// Open (or create) the on-disk DB under the app-support directory.
  /// Fail-soft: a failure leaves the service disabled with [initError] set.
  Future<void> init({String? dbPath}) async {
    try {
      final path = dbPath ??
          p.join((await getApplicationSupportDirectory()).path, 'audit.db');
      _open(sqlite3.open(path));
    } catch (e) {
      initError = '$e';
      debugPrint('[AuditService] init failed: $e');
    }
  }

  /// In-memory DB for tests.
  void initInMemory() => _open(sqlite3.openInMemory());

  void _open(Database db) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute(_schema);
    db.execute('CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit_events(ts)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_host ON audit_events(host_id)');
    _db = db;
  }

  void record(AuditEvent e) {
    final db = _db;
    if (db == null) return;
    try {
      db.execute(
        'INSERT INTO audit_events '
        '(ts, type, host_id, host_label, username, session_id, command, '
        'exit_code, meta) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          e.ts.millisecondsSinceEpoch,
          e.type.name,
          e.hostId,
          e.hostLabel,
          e.username,
          e.sessionId,
          e.command == null ? null : AuditRedactor.redact(e.command!),
          e.exitCode,
          e.meta.isEmpty ? null : jsonEncode(e.meta),
        ],
      );
    } catch (err) {
      debugPrint('[AuditService] record failed: $err'); // never rethrow
    }
  }

  List<AuditEvent> query(AuditFilter f, {int limit = 200, int offset = 0}) {
    final db = _db;
    if (db == null) return const [];
    try {
      final (where, args) = f.toWhere();
      final rows = db.select(
        'SELECT * FROM audit_events $where '
        'ORDER BY ts DESC, id DESC LIMIT ? OFFSET ?',
        [...args, limit, offset],
      );
      return rows.map(AuditEvent.fromRow).toList();
    } catch (err) {
      debugPrint('[AuditService] query failed: $err');
      return const [];
    }
  }

  /// Delete rows older than [retentionDays]; `<= 0` keeps forever.
  void prune(int retentionDays) {
    if (retentionDays <= 0) return;
    try {
      _db?.execute('DELETE FROM audit_events WHERE ts < ?', [
        DateTime.now()
            .subtract(Duration(days: retentionDays))
            .millisecondsSinceEpoch
      ]);
    } catch (err) {
      debugPrint('[AuditService] prune failed: $err');
    }
  }

  void clearAll() {
    try {
      _db?.execute('DELETE FROM audit_events');
    } catch (err) {
      debugPrint('[AuditService] clearAll failed: $err');
    }
  }

  List<AuditEvent> _allMatching(AuditFilter f) {
    final db = _db;
    if (db == null) return const [];
    final (where, args) = f.toWhere();
    final rows = db.select(
        'SELECT * FROM audit_events $where ORDER BY ts DESC, id DESC', args);
    return rows.map(AuditEvent.fromRow).toList();
  }

  static String _csvField(String v) =>
      (v.contains(',') || v.contains('"') || v.contains('\n'))
          ? '"${v.replaceAll('"', '""')}"'
          : v;

  String exportCsv(AuditFilter f) {
    const header = 'ts,type,host_label,username,session_id,command,'
        'exit_code,meta';
    final lines = [
      header,
      for (final e in _allMatching(f)) e.toCsvRow().map(_csvField).join(','),
    ];
    return lines.join('\n');
  }

  String exportJson(AuditFilter f) =>
      jsonEncode([for (final e in _allMatching(f)) e.toJson()]);

  void dispose() {
    _db?.dispose();
    _db = null;
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/services/audit_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/lib/services/audit_service.dart app/test/services/audit_service_test.dart
git commit -m "feat: AuditService — sqlite3 audit trail with redaction and export"
```

---

### Task 4: SshService.exec audit + auditSource threading

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (exec, ~line 756; add `audit` field near `hookBus`)
- Modify callers: `app/lib/main.dart:74`, `app/lib/plugins/plugin_context_impl.dart:61`, `app/lib/widgets/bulk/bulk_run_dialog.dart:38`, `app/lib/services/container_service.dart`, `app/lib/services/network_stats_service.dart:30`, `app/lib/services/mcp_gateway_service.dart`, `app/lib/services/cloudflare_tunnel_service.dart`, `app/lib/services/mail_catcher_service.dart`, `app/lib/services/web_tools_service.dart:18`
- Test: `app/test/services/ssh_service_exec_audit_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

class _ExecClient implements SSHClient {
  @override
  Future<SSHCommandResult> runWithResult(String command,
      {bool runInPty = false, Map<String, String>? environment}) async {
    return SSHCommandResult(
      stdout: Uint8List.fromList('out'.codeUnits),
      stderr: Uint8List(0),
      exitCode: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('exec records a redacted audit event with source and exit code',
      () async {
    final audit = AuditService()..initInMemory();
    final svc = SshService(StorageService())..audit = audit;
    final host = Host(label: 'prod', host: 'p.com', username: 'root');
    svc.debugSetClient(host.id, _ExecClient());

    await svc.exec(host, 'export TOKEN=abc && ls', auditSource: 'bulk');

    final rows = audit.query(const AuditFilter(type: 'exec'));
    expect(rows.length, 1);
    expect(rows.single.command, 'export TOKEN=[REDACTED] && ls');
    expect(rows.single.exitCode, 0);
    expect(rows.single.hostLabel, 'prod');
    expect(rows.single.meta['source'], 'bulk');
    audit.dispose();
  });

  test('default source is app; auditSource null skips auditing', () async {
    final audit = AuditService()..initInMemory();
    final svc = SshService(StorageService())..audit = audit;
    final host = Host(label: 'h', host: 'h.com', username: 'u');
    svc.debugSetClient(host.id, _ExecClient());

    await svc.exec(host, 'uptime');
    await svc.exec(host, 'cat /proc/net/dev', auditSource: null);

    final rows = audit.query(const AuditFilter(type: 'exec'));
    expect(rows.length, 1);
    expect(rows.single.meta['source'], 'app');
    audit.dispose();
  });
}
```

Note: if `SSHCommandResult`'s constructor differs in the dartssh2 fork (check
`packages/dartssh2` — `runWithResult` return type), adapt the `_ExecClient`
fake to construct whatever `client.runWithResult` actually returns
(`result.stdout` / `result.stderr` are byte lists, `result.exitCode` int?).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/ssh_service_exec_audit_test.dart`
Expected: FAIL — `audit` and `auditSource` not defined.

- [ ] **Step 3: Implement in SshService**

Near the other public collaborator fields (`hookBus`, `shellIntegration`):

```dart
  /// Audit trail sink; null disables auditing (tests, early startup).
  AuditService? audit;
```

with `import 'audit_service.dart';` and `import '../models/audit_event.dart';`.

Change `exec` (line ~756):

```dart
  /// [auditSource] tags the audit event ('app', 'bulk', 'devops',
  /// 'plugin:…'); pass null for internal polling probes that would flood
  /// the log (network stats, OS detection).
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async {
```

and after `execResult` is built (before the `command.after` hook):

```dart
    if (auditSource != null) {
      audit?.record(AuditEvent.now(
        type: AuditEventType.exec,
        host: host,
        command: originalCommand,
        exitCode: execResult.exitCode,
        meta: {'source': auditSource},
      ));
    }
```

Wrap the connect/run portion so failures are audited too — replace:

```dart
    final originalCommand = cmd;
    final client = await _ensureClient(host);
    final result = await client.runWithResult(cmd);
```

with:

```dart
    final originalCommand = cmd;
    final SSHClient client;
    final dynamic result;
    try {
      client = await _ensureClient(host);
      result = await client.runWithResult(cmd);
    } catch (e) {
      if (auditSource != null) {
        audit?.record(AuditEvent.now(
          type: AuditEventType.exec,
          host: host,
          command: originalCommand,
          meta: {'source': auditSource, 'error': '$e'},
        ));
      }
      rethrow;
    }
```

If `detectOs` calls `this.exec(...)`, add `auditSource: null` to those
internal calls (grep `exec(` inside `ssh_service.dart`).

- [ ] **Step 4: Thread auditSource through callers**

- `app/lib/main.dart:74` (`_SshBridgeAdapter.execCommand`):
  `exec(session.host, command, auditSource: 'plugin:js')`
- `app/lib/plugins/plugin_context_impl.dart:61` (`execCommand`):
  `_ssh.exec(host, command, auditSource: 'plugin')`
- `app/lib/widgets/bulk/bulk_run_dialog.dart:38` — replace the tear-off:
  ```dart
  final svc = context.read<SshService>();
  ... BulkActionService(
      exec: (host, cmd) => svc.exec(host, cmd, auditSource: 'bulk'));
  ```
  (adapt to the actual surrounding expression; keep the signature identical)
- `app/lib/services/container_service.dart` (5 sites), `mcp_gateway_service.dart` (2), `cloudflare_tunnel_service.dart` (3), `mail_catcher_service.dart` (4), `web_tools_service.dart` (1): add `auditSource: 'devops'`.
- `app/lib/services/network_stats_service.dart:30`: add `auditSource: null` with comment `// periodic poll — auditing would flood the log`.

- [ ] **Step 5: Run tests**

Run: `cd app && flutter test test/services/ssh_service_exec_audit_test.dart && flutter analyze`
Expected: PASS, 0 analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add -A app/lib app/test/services/ssh_service_exec_audit_test.dart
git commit -m "feat: audit exec events with per-caller source tagging"
```

---

### Task 5: SessionProvider connect/disconnect audit

**Files:**
- Modify: `app/lib/providers/session_provider.dart` (`_doConnect` ~141/180, `closeSession` ~252, the two `onSessionDropped` sites ~169/185)
- Test: `app/test/providers/session_provider_audit_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Reuse the `_CapturingSsh` fake pattern from
`app/test/providers/session_provider_template_test.dart` (same imports);
name it `_FakeSsh` here:

```dart
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _NullClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSsh extends SshService {
  _FakeSsh({this.failConnect = false}) : super(StorageService());
  final bool failConnect;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    if (failConnect) throw Exception('refused');
    return _NullClient();
  }

  @override
  Future<void> openShell(SshSession session,
      {bool useTmux = false, String termType = 'xterm-256color'}) async {}

  @override
  void disconnectSession(String sessionId) {}

  @override
  Future<void> disconnect(String hostId) async {}
}

Host _host() => Host(
    label: 'prod', host: 'p.com', username: 'root', detectedOs: 'ubuntu');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('successful connect records a connect event', () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())
      ..audit = audit;
    await p.connect(_host());

    final connects = audit.query(const AuditFilter(type: 'connect'));
    expect(connects.length, 1);
    expect(connects.single.hostLabel, 'prod');
    expect(connects.single.meta.containsKey('error'), isFalse);
    p.dispose();
    audit.dispose();
  });

  test('final connect failure records connect with error; no spam', () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(failConnect: true), TabMetadataService())
      ..audit = audit;
    // auto-reconnect off → first failure is final
    await p.connect(_host());

    final connects = audit.query(const AuditFilter(type: 'connect'));
    expect(connects.length, 1);
    expect(connects.single.meta['error'], contains('refused'));
    expect(connects.single.meta['attempts'], 1);
    p.dispose();
    audit.dispose();
  });

  test('shell close without reconnect records a dropped disconnect',
      () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())
      ..audit = audit;
    await p.connect(_host()); // openShell returns immediately → drop path

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.length, 1);
    expect(dis.single.meta['reason'], 'dropped');
    p.dispose();
    audit.dispose();
  });

  test('closeSession records a user-closed disconnect', () async {
    final audit = AuditService()..initInMemory();
    final p = SessionProvider(_FakeSsh(), TabMetadataService())
      ..audit = audit;
    final host = _host();
    await p.connect(host);
    audit.clearAll(); // ignore the connect/drop rows from setup
    // re-add a session in connected state to close it cleanly:
    await p.connect(host);
    final id = p.sessions.last.id;
    p.closeSession(id);

    final dis = audit.query(const AuditFilter(type: 'disconnect'));
    expect(dis.map((e) => e.meta['reason']), contains('user-closed'));
    p.dispose();
    audit.dispose();
  });
}
```

(`disconnectSession` / `disconnect` overrides: check the real method names in
`SshService` — `closeSession` calls `_ssh.disconnectSession(sessionId)` and
`_ssh.disconnect(hostId)`; override both as no-ops so the fake never touches
the network.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/session_provider_audit_test.dart`
Expected: FAIL — `audit` not defined on SessionProvider.

- [ ] **Step 3: Implement**

In `app/lib/providers/session_provider.dart`, add near the other callback
fields, with imports `../models/audit_event.dart` and
`../services/audit_service.dart`:

```dart
  /// Audit trail sink; null disables auditing.
  AuditService? audit;
```

In `_doConnect` after `session.status = SessionStatus.connected;`:

```dart
      audit?.record(AuditEvent.now(
          type: AuditEventType.connect, host: host, sessionId: session.id));
```

In the catch block's **no-retry** branch (where `session.status = SessionStatus.error;` is set):

```dart
        // Final failure only — an unlimited-retry outage must not write
        // one audit row per attempt tick.
        audit?.record(AuditEvent.now(
          type: AuditEventType.connect,
          host: host,
          sessionId: session.id,
          meta: {'error': '$e', 'attempts': attempt},
        ));
```

At the two `onSessionDropped` sites:

```dart
        // ~line 169 (graceful close, no reconnect):
        audit?.record(AuditEvent.now(
            type: AuditEventType.disconnect,
            host: host,
            sessionId: session.id,
            meta: const {'reason': 'dropped'}));
        // ~line 185 (error path), before onSessionDropped:
        audit?.record(AuditEvent.now(
            type: AuditEventType.disconnect,
            host: host,
            sessionId: session.id,
            meta: {
              'reason': 'dropped',
              if (session.errorMessage != null) 'error': session.errorMessage,
            }));
```

In `closeSession`, in the SSH branch (after the session lookup, only when a
session was found and is an `SshSession`):

```dart
    final ssh = sshSessions.where((s) => s.id == sessionId).firstOrNull;
    if (ssh != null) {
      audit?.record(AuditEvent.now(
          type: AuditEventType.disconnect,
          host: ssh.host,
          sessionId: sessionId,
          meta: const {'reason': 'user-closed'}));
    }
```

(the existing `hostId` lookup can reuse `ssh?.host.id`.)

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/providers/session_provider_audit_test.dart test/providers/session_provider_test.dart test/providers/session_provider_template_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_audit_test.dart
git commit -m "feat: audit connect/disconnect session events"
```

---

### Task 6: Input capture — input bar + plugin sendInput

**Files:**
- Modify: `app/lib/widgets/terminal_input_bar.dart` (`_submit`, ~line 78)
- Modify: `app/lib/plugins/plugin_context_impl.dart` (`sendInput`, ~line 71)
- Modify: `app/lib/main.dart` (`_SshBridgeAdapter.sendInput` — the JS-plugin path)
- Test: `app/test/widgets/terminal_input_bar_audit_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/terminal_input_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('submitting a command records an input audit event',
      (tester) async {
    final audit = AuditService()..initInMemory();
    final sessions =
        SessionProvider(SshService(StorageService()), TabMetadataService());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
        ChangeNotifierProvider.value(value: sessions),
        Provider<AuditService>.value(value: audit),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TerminalInputBar(sessionId: 's1', onSubmit: (_) {}),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'systemctl restart nginx');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final rows = audit.query(const AuditFilter(type: 'input'));
    expect(rows.length, 1);
    expect(rows.single.command, 'systemctl restart nginx');
    expect(rows.single.meta['source'], 'input-bar');
    sessions.dispose();
    audit.dispose();
  });
}
```

(Check `TerminalInputBar`'s actual constructor — it takes `sessionId` and
`onSubmit`; if it requires more parameters, pass minimal fakes. If
`CommandHistoryProvider`'s constructor needs arguments, mirror its existing
test setup from `app/test/providers/command_history_provider_test.dart`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/terminal_input_bar_audit_test.dart`
Expected: FAIL — no audit row recorded.

- [ ] **Step 3: Implement**

`app/lib/widgets/terminal_input_bar.dart` — in `_submit`, after the
`recordCommand` line, with imports `../models/audit_event.dart`,
`../providers/session_provider.dart`, `../services/audit_service.dart`:

```dart
    try {
      final audit = context.read<AuditService>();
      final host =
          context.read<SessionProvider>().hostForSession(widget.sessionId);
      audit.record(AuditEvent.now(
        type: AuditEventType.input,
        host: host,
        sessionId: widget.sessionId,
        command: command,
        meta: const {'source': 'input-bar'},
      ));
    } on ProviderNotFoundException {
      // Panes pumped without audit wiring (tests).
    }
```

`app/lib/plugins/plugin_context_impl.dart` — add an optional collaborator
and record after a successful send (mirror however the class already takes
`_ssh`/`_sessions`; add `this.audit` as an optional constructor parameter
and update the construction site in `PluginProvider`):

```dart
  final AuditService? audit;
  ...
  // at the end of sendInput, after the successful _ssh.sendInput call:
  audit?.record(AuditEvent.now(
    type: AuditEventType.input,
    host: session.host,
    sessionId: sessionId,
    command: text,
    meta: const {'source': 'plugin'},
  ));
```

`app/lib/main.dart` — in `_SshBridgeAdapter.sendInput` (the JS path), record
the same way with `meta: const {'source': 'plugin:js'}` (the adapter already
resolves the session; reuse its host lookup).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/widgets/terminal_input_bar_audit_test.dart && flutter analyze`
Expected: PASS, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add -A app/lib app/test/widgets/terminal_input_bar_audit_test.dart
git commit -m "feat: audit input-bar and plugin sendInput commands"
```

---

### Task 7: Retention setting + Settings UI

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Modify: `app/lib/widgets/settings_screen.dart`
- Test: extend `app/test/settings_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `app/test/settings_provider_test.dart` (mirror the file's existing
style):

```dart
  test('auditRetentionDays defaults to 90 and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsProvider();
    await Future<void>.delayed(Duration.zero); // let _load run
    expect(s.auditRetentionDays, 90);
    await s.save(auditRetentionDays: 30);
    expect(s.auditRetentionDays, 30);
    final s2 = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(s2.auditRetentionDays, 30);
  });
```

(If the file constructs `SettingsProvider` differently or exposes a load
future, follow its existing pattern.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/settings_provider_test.dart`
Expected: FAIL — `auditRetentionDays` not defined.

- [ ] **Step 3: Implement**

`app/lib/providers/settings_provider.dart` — follow the `reconnectAttempts`
pattern exactly:

```dart
  /// Audit log retention in days; 0 = keep forever.
  int auditRetentionDays = 90;
  // _load():
  auditRetentionDays = prefs.getInt('auditRetentionDays') ?? 90;
  // save() parameter + body:
  int? auditRetentionDays,
  if (auditRetentionDays != null) this.auditRetentionDays = auditRetentionDays;
  await prefs.setInt('auditRetentionDays', this.auditRetentionDays);
```

`app/lib/widgets/settings_screen.dart` — add an **Audit** section following
the screen's existing section pattern: a dropdown
(30 / 90 / 365 / `0` rendered as "Keep forever") bound to
`settings.auditRetentionDays` calling
`settings.save(auditRetentionDays: v)`, and a "Clear audit log" button that
shows a confirm dialog and then calls
`context.read<AuditService>().clearAll()` (import
`../services/audit_service.dart`; read inside a try/catch on
`ProviderNotFoundException` like the input bar, so settings tests without
the provider stay green).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/settings_provider_test.dart && flutter analyze`
Expected: PASS, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/lib/widgets/settings_screen.dart app/test/settings_provider_test.dart
git commit -m "feat: audit retention setting with Settings section"
```

---

### Task 8: AuditProvider

**Files:**
- Create: `app/lib/providers/audit_provider.dart`
- Test: `app/test/providers/audit_provider_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/providers/audit_provider.dart';
import 'package:yourssh/services/audit_service.dart';

void main() {
  late AuditService svc;
  late AuditProvider p;

  setUp(() {
    svc = AuditService()..initInMemory();
    for (var i = 0; i < 250; i++) {
      svc.record(AuditEvent(
          ts: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          type: i.isEven ? AuditEventType.exec : AuditEventType.connect,
          hostId: i % 3 == 0 ? 'h1' : 'h2',
          hostLabel: i % 3 == 0 ? 'alpha' : 'beta',
          command: i.isEven ? 'cmd $i' : null));
    }
    p = AuditProvider(svc)..refresh();
  });

  tearDown(() {
    p.dispose();
    svc.dispose();
  });

  test('refresh loads the first page (200), loadMore appends the rest', () {
    expect(p.events.length, 200);
    expect(p.hasMore, isTrue);
    p.loadMore();
    expect(p.events.length, 250);
    expect(p.hasMore, isFalse);
  });

  test('type and host filters narrow results and reset paging', () {
    p.setType('connect');
    expect(p.events.every((e) => e.type == AuditEventType.connect), isTrue);
    p.setHost('h1');
    expect(p.events.every((e) => e.hostId == 'h1'), isTrue);
    p.setType(null);
    p.setHost(null);
    expect(p.events.length, 200);
  });

  test('search filters on command text', () {
    p.setSearch('cmd 24');
    expect(p.events.map((e) => e.command),
        everyElement(anyOf(contains('cmd 24'))));
    expect(p.events, isNotEmpty);
  });

  test('clearAll empties the list', () {
    p.clearAll();
    expect(p.events, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/audit_provider_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `app/lib/providers/audit_provider.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../models/audit_event.dart';
import '../services/audit_service.dart';

/// Filter state + lazy paging for the audit viewer. Pages are 200 rows;
/// [hasMore] is true while a full page came back.
class AuditProvider extends ChangeNotifier {
  AuditProvider(this._service);

  final AuditService _service;
  static const _pageSize = 200;

  final List<AuditEvent> events = [];
  bool hasMore = false;

  String? hostId;
  String? type;

  /// 0 = all; otherwise events newer than [rangeDays] days (1 = today,
  /// i.e. since local midnight).
  int rangeDays = 0;
  String search = '';

  String? get initError => _service.initError;
  bool get isAvailable => _service.isAvailable;

  AuditFilter get _filter {
    int? fromTs;
    if (rangeDays == 1) {
      final now = DateTime.now();
      fromTs = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    } else if (rangeDays > 1) {
      fromTs = DateTime.now()
          .subtract(Duration(days: rangeDays))
          .millisecondsSinceEpoch;
    }
    return AuditFilter(
      hostId: hostId,
      type: type,
      fromTs: fromTs,
      search: search.trim().isEmpty ? null : search.trim(),
    );
  }

  void refresh() {
    events
      ..clear()
      ..addAll(_service.query(_filter, limit: _pageSize));
    hasMore = events.length == _pageSize;
    notifyListeners();
  }

  void loadMore() {
    final page =
        _service.query(_filter, limit: _pageSize, offset: events.length);
    events.addAll(page);
    hasMore = page.length == _pageSize;
    notifyListeners();
  }

  void setHost(String? id) {
    hostId = id;
    refresh();
  }

  void setType(String? t) {
    type = t;
    refresh();
  }

  void setRange(int days) {
    rangeDays = days;
    refresh();
  }

  void setSearch(String s) {
    search = s;
    refresh();
  }

  String exportCsv() => _service.exportCsv(_filter);
  String exportJson() => _service.exportJson(_filter);

  void clearAll() {
    _service.clearAll();
    refresh();
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/providers/audit_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/audit_provider.dart app/test/providers/audit_provider_test.dart
git commit -m "feat: AuditProvider filter/paging state"
```

---

### Task 9: AuditScreen + navigation

**Files:**
- Create: `app/lib/widgets/audit_screen.dart`
- Modify: `app/lib/screens/main_screen.dart` (enum line ~51, sidebar nav items ~845, content mapping ~664)
- Test: `app/test/widgets/audit_screen_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/providers/audit_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/widgets/audit_screen.dart';

void main() {
  testWidgets('renders rows and narrows by type filter', (tester) async {
    final svc = AuditService()..initInMemory();
    svc.record(AuditEvent.now(
        type: AuditEventType.exec, command: 'docker ps', exitCode: 0));
    svc.record(AuditEvent.now(type: AuditEventType.connect));
    final provider = AuditProvider(svc)..refresh();

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: provider)],
      child: const MaterialApp(home: Scaffold(body: AuditScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('docker ps'), findsOneWidget);
    expect(find.text('connect'), findsWidgets);

    provider.setType('connect');
    await tester.pumpAndSettle();
    expect(find.text('docker ps'), findsNothing);

    provider.dispose();
    svc.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/audit_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the screen**

Create `app/lib/widgets/audit_screen.dart` (styling mirrors the other
screens: `AppColors`, dense rows; adapt small details to compile):

```dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/audit_event.dart';
import '../providers/audit_provider.dart';
import '../theme/app_theme.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<AuditProvider>().refresh());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _export(BuildContext context, {required bool csv}) async {
    final provider = context.read<AuditProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(
          suggestedName: csv ? 'audit-export.csv' : 'audit-export.json');
      if (location == null) return;
      final content = csv ? provider.exportCsv() : provider.exportJson();
      await File(location.path).writeAsString(content);
      messenger.showSnackBar(
          SnackBar(content: Text('Exported to ${location.path}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final provider = context.read<AuditProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Clear audit log?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: const Text('All recorded events will be deleted.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Clear', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) provider.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuditProvider>();

    if (!provider.isAvailable) {
      return Center(
        child: Text(
          'Audit log unavailable: ${provider.initError ?? 'not initialized'}',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Text('AUDIT LOG',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2)),
            const Spacer(),
            TextButton.icon(
                onPressed: () => _export(context, csv: true),
                icon: const Icon(Icons.download, size: 14),
                label: const Text('CSV', style: TextStyle(fontSize: 12))),
            TextButton.icon(
                onPressed: () => _export(context, csv: false),
                icon: const Icon(Icons.download, size: 14),
                label: const Text('JSON', style: TextStyle(fontSize: 12))),
            TextButton.icon(
                onPressed: () => _confirmClear(context),
                icon: const Icon(Icons.delete_outline,
                    size: 14, color: Colors.red),
                label: const Text('Clear',
                    style: TextStyle(fontSize: 12, color: Colors.red))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            DropdownButton<String?>(
              value: provider.type,
              hint: const Text('Type',
                  style:
                      TextStyle(color: AppColors.textTertiary, fontSize: 12)),
              dropdownColor: AppColors.card,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem(value: null, child: Text('All types')),
                for (final t in AuditEventType.values)
                  DropdownMenuItem(value: t.name, child: Text(t.name)),
              ],
              onChanged: provider.setType,
            ),
            const SizedBox(width: 16),
            for (final (label, days) in [
              ('Today', 1),
              ('7d', 7),
              ('30d', 30),
              ('All', 0)
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: provider.rangeDays == days,
                  onSelected: (_) => provider.setRange(days),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  hintText: 'Search command or host…',
                  hintStyle:
                      TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  prefixIcon: Icon(Icons.search, size: 14),
                  isDense: true,
                ),
                onSubmitted: provider.setSearch,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: provider.events.isEmpty
              ? const Center(
                  child: Text('No audit events',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 13)))
              : ListView.builder(
                  itemCount:
                      provider.events.length + (provider.hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= provider.events.length) {
                      return TextButton(
                          onPressed: provider.loadMore,
                          child: const Text('Load more'));
                    }
                    return _AuditRow(event: provider.events[i]);
                  },
                ),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEvent event;
  const _AuditRow({required this.event});

  Color get _typeColor => switch (event.type) {
        AuditEventType.connect => Colors.green,
        AuditEventType.disconnect => Colors.orange,
        AuditEventType.exec => Colors.blue,
        AuditEventType.input => Colors.purple,
      };

  @override
  Widget build(BuildContext context) {
    final ts = event.ts.toLocal();
    final time = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}';
    final source = event.meta['source'];
    final error = event.meta['error'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Row(children: [
        SizedBox(
            width: 150,
            child: Text(time,
                style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                    fontFamily: 'monospace'))),
        Container(
          width: 84,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
              color: _typeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4)),
          child: Text(event.type.name,
              style: TextStyle(color: _typeColor, fontSize: 11)),
        ),
        const SizedBox(width: 10),
        SizedBox(
            width: 160,
            child: Text(
                event.hostLabel == null
                    ? '—'
                    : '${event.username ?? ''}@${event.hostLabel}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))),
        Expanded(
            child: Text(
                event.command ?? (error != null ? 'error: $error' : ''),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace'))),
        if (source != null)
          Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('$source',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 11))),
        if (event.exitCode != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('exit ${event.exitCode}',
                style: TextStyle(
                    color: event.exitCode == 0 ? Colors.green : Colors.red,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
      ]),
    );
  }
}
```

(If `Color.withValues` is unavailable on the project's Flutter version, use
`withOpacity(0.15)`.)

- [ ] **Step 4: Wire navigation**

`app/lib/screens/main_screen.dart`:
- Enum (line ~51): add `audit` → `enum NavSection { hosts, keychain, portForwarding, sftp, knownHosts, recordings, audit, settings, plugins }`
- Sidebar: next to the Recordings nav item add
  `_navItem(Icons.receipt_long_outlined, 'Audit Log', NavSection.audit),`
- Content mapping (`_buildContent`, ~line 664): add the case for
  `NavSection.audit` → `const AuditScreen()` following exactly how
  `RecordingLibraryScreen` is mounted, with
  `import '../widgets/audit_screen.dart';`

- [ ] **Step 5: Run tests**

Run: `cd app && flutter test test/widgets/audit_screen_test.dart && flutter analyze`
Expected: PASS, 0 issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/audit_screen.dart app/lib/screens/main_screen.dart app/test/widgets/audit_screen_test.dart
git commit -m "feat: audit log viewer screen with filters and export"
```

---

### Task 10: main.dart wiring + startup prune

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Construct and inject**

Near the other service constructions (lines ~155, where `_ssh` is built):

```dart
  late final AuditService _audit;
  late final AuditProvider _auditProvider;
  // in the init block, after _ssh and _sessionProvider exist:
  _audit = AuditService();
  _auditProvider = AuditProvider(_audit);
  _ssh.audit = _audit;
  _sessionProvider.audit = _audit;
  unawaited(_audit.init().then((_) async {
    final prefs = await SharedPreferences.getInstance();
    _audit.prune(prefs.getInt('auditRetentionDays') ?? 90);
  }));
```

with imports `services/audit_service.dart`, `providers/audit_provider.dart`
(and `dart:async` for `unawaited` if not present).

In the `MultiProvider` list (~line 408):

```dart
        Provider<AuditService>.value(value: _audit),
        ChangeNotifierProvider<AuditProvider>.value(value: _auditProvider),
```

Pass `audit: _audit` to the `PluginContextImpl` construction site (wherever
`PluginProvider` builds contexts — follow the existing parameter threading),
and confirm `_SshBridgeAdapter` got its exec/sendInput audit from Task 4/6.

Dispose: if main.dart has a dispose/shutdown path for services, call
`_audit.dispose()` there; otherwise OS teardown is fine (WAL is
crash-safe).

- [ ] **Step 2: Verify**

Run: `cd app && flutter analyze && flutter test`
Expected: 0 issues, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: wire AuditService into app startup with retention prune"
```

---

### Task 11: Full verification + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full run**

Run: `cd app && flutter analyze && flutter test`
Expected: 0 issues, all tests pass. Optionally `flutter build macos --debug`
to confirm the sqlite3_flutter_libs pod integrates.

- [ ] **Step 2: Update CLAUDE.md**

- **Providers**: add
  `- AuditProvider — filter state + lazy paging (200/page) over AuditService for the audit viewer`
- **Services**: add
  `- AuditService / AuditRedactor — local SQLite audit trail (sqlite3, WAL, <app-support>/audit.db): connect/disconnect/exec/input events with denormalized host fields; commands pass AuditRedactor (pure regex masking: key=value secrets incl. prefixed PGPASSWORD=, Bearer tokens, sshpass -p, mysql/mariadb attached -p, URL userinfo) before insert; every write fail-soft; SshService.exec takes auditSource ('app' default, 'bulk'/'devops'/'plugin:…' threaded by callers, null = skip for polling probes like network stats); retention pruned at startup (auditRetentionDays, default 90, 0 = forever); CSV/JSON export of the filtered view`
- **Key models**: add `AuditEvent` to the model list line.
- **Navigation**: add `audit` to the `NavSection` enum list.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: internal audit log in CLAUDE.md"
```

---

## Self-review notes (already applied)

- **Spec coverage:** storage/schema (T3), redaction (T1, applied inside `record` in T3), exec capture incl. `auditSource` + flood-guard `null` (T4), connect/disconnect incl. no-retry-spam rule (T5), input-bar + plugin sendInput + JS path (T6), retention + Settings section (T7, prune wiring T10), viewer + filters + search + export + clear + unavailable state (T8/T9), fail-soft everywhere (T3 test), wiring (T10), docs (T11).
- **Type consistency:** `AuditEventType` (T2) used in T4–T9; `AuditFilter` (T3) used in T4–T8 tests; `AuditService.initInMemory/record/query/prune/clearAll/exportCsv/exportJson/dispose` consistent across tasks; `AuditProvider.setType/setHost/setRange/setSearch/refresh/loadMore/clearAll` (T8) match T9's screen.
- **Deviation from spec:** psql dropped from the `-p` redaction pattern (it's the port flag); covered by `PGPASSWORD=` via the prefixed key=value pattern. Network-stats polling excluded from auditing via `auditSource: null` — keeps the log meaningful (spec's "stays fast" goal).
- **Known risk:** fakes for `runWithResult` (T4) and input-bar constructor (T6) are written from explored signatures; adapt at execution if the real signatures differ — the assertions stand.
