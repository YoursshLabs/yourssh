// 11 audit log.
import 'nav.dart';
import 'sections.dart';

const s = '11-audit-log';

Future<void> runAudit(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Audit Log');
  await sleepPump(t, 1000);
  await c.snap('$s/01-rows', 'Audit log: connect / exec / disconnect rows with host, source and exit code');
  await step(c.notes, 'type filter', () async {
    await tapKey(t, 'audit-type', wait: 600);
    await c.snap('$s/02-type-menu', 'Event type filter menu');
    await pressEscape(t);
  });
  await step(c.notes, 'range', () async {
    await tapKey(t, 'audit-range-1', wait: 600);
    await c.snap('$s/03-range-today', 'Range chip: Today selected');
    await tapKey(t, 'audit-range-0', wait: 500);
  });
  await step(c.notes, 'search', () async {
    await typeKey(t, 'audit-search', 'hostname');
    await sleepPump(t, 800);
    await c.snap('$s/04-search', 'Search for "hostname" narrows the rows');
    await typeKey(t, 'audit-search', '');
    await sleepPump(t, 500);
  });
  await step(c.notes, 'export', () async {
    await tapKey(t, 'audit-export-csv', wait: 1200);
    await c.snap('$s/05-export-csv', 'CSV export (save dialog answered by the harness; confirmation toast)');
  });
  await step(c.notes, 'clear confirm', () async {
    await tapKey(t, 'audit-clear', wait: 700);
    await c.snap('$s/06-clear-confirm', 'Clear audit log confirmation');
    await tapText(t, 'Cancel', wait: 500);
  });
}
