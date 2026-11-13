// 09 known hosts.
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '09-known-hosts';

Future<void> runKnownHosts(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Known Hosts');
  await c.snap('$s/01-list', 'Known hosts: pinned host keys created by the connections made so far');
  await step(c.notes, 'hover', () async {
    await hoverOn(t, find.textContaining('127.0.0.1').first);
    await c.snap('$s/02-hover-actions', 'Row hover: copy fingerprint / remove');
  });
  await step(c.notes, 'remove', () async {
    await tapTooltip(t, 'Remove', wait: 700);
    await c.snap('$s/03-remove-confirm', '"Remove host key?" confirmation (Cancel focused)');
    await tapText(t, 'Cancel', wait: 500);
  });
}
