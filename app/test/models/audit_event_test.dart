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
    expect(e.toCsvRow().length, AuditEvent.kCsvColumns.length);
    expect(e.toJson().keys,
        containsAll(['ts', 'type', 'command', 'meta', 'hostLabel']));
  });

  test('fromRow degrades malformed meta to empty instead of throwing', () {
    final e = AuditEvent.fromRow({
      'id': 1,
      'ts': 0,
      'type': 'exec',
      'meta': '{not json',
    });
    expect(e.meta, isEmpty);
  });
}
