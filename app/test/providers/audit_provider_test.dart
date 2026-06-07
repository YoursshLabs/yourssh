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
    expect(p.events, isNotEmpty);
    expect(p.events.every((e) => e.command!.contains('cmd 24')), isTrue);
  });

  test('clearAll empties the list', () {
    p.clearAll();
    expect(p.events, isEmpty);
  });
}
