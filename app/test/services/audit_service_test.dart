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
    svc.record(
        ev(AuditEventType.connect, hostId: 'h1', ts: DateTime(2026, 1, 1)));
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
    svc.record(
        ev(AuditEventType.connect, hostId: 'h2', ts: DateTime(2026, 2, 2)));

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
    expect(
        () => svc.record(ev(AuditEventType.exec, cmd: 'x')), returnsNormally);
    expect(svc.query(const AuditFilter()), isEmpty);
  });

  test('string meta values are redacted before insert', () {
    svc.record(AuditEvent(
        ts: DateTime.now(),
        type: AuditEventType.exec,
        command: 'ls',
        meta: const {
          'source': 'app',
          'error': 'auth failed for https://user:hunter2@db.example.com',
        }));
    final row = svc.query(const AuditFilter()).single;
    expect(row.meta['error'], isNot(contains('hunter2')));
    expect(row.meta['error'], contains('[REDACTED]'));
    expect(row.meta['source'], 'app');
  });

  test('CSV quotes carriage returns', () {
    svc.record(ev(AuditEventType.exec, cmd: 'printf a\rb'));
    final dataLine = svc.exportCsv(const AuditFilter());
    // The \r field must be quoted so it cannot split the record.
    expect(dataLine, contains('"printf a\rb"'));
  });

  test('keyset pagination (before anchor) never duplicates across new rows',
      () {
    for (var i = 0; i < 5; i++) {
      svc.record(ev(AuditEventType.exec,
          cmd: 'c$i', ts: DateTime(2026, 1, 1 + i)));
    }
    final page1 = svc.query(const AuditFilter(), limit: 2);
    expect(page1.map((e) => e.command), ['c4', 'c3']);
    // A new row lands AFTER page 1 was fetched (highest ts).
    svc.record(ev(AuditEventType.exec, cmd: 'c9', ts: DateTime(2026, 2, 1)));
    final last = page1.last;
    final page2 = svc.query(const AuditFilter(),
        limit: 2, beforeTs: last.ts.millisecondsSinceEpoch, beforeId: last.id);
    expect(page2.map((e) => e.command), ['c2', 'c1'],
        reason: 'anchor paging must not re-serve or skip rows');
  });
}
