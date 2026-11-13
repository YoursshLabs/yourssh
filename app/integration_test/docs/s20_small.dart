// 20 minimum-size (900x600) variants.
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '20-small-window';

Future<void> runSmall(JourneyContext c) async {
  final t = c.t;
  await setWindow(900, 600);
  await sleepPump(t, 1000);
  await navTo(t, 'Hosts');
  await c.snap('$s/01-dashboard-900', 'Dashboard at the 900x600 minimum window (toolbar collapses to icons)');
  await step(c.notes, 'panel', () async {
    await tapText(t, 'New host', index: 0, wait: 800);
    await c.snap('$s/02-new-host-900', 'New host panel at 900x600');
    await tapTooltip(t, 'Close', wait: 500);
  });
  await step(c.notes, 'terminal', () async {
    await t.tap(find.textContaining('Demo Server · demo').first, warnIfMissed: false);
    await sleepPump(t, 1000);
    await c.snap('$s/03-terminal-900', 'Terminal at 900x600');
  });
  await step(c.notes, 'sftp', () async {
    await navTo(t, 'SFTP', wait: 1000);
    await c.snap('$s/04-sftp-900', 'SFTP at 900x600');
  });
  await step(c.notes, 'settings', () async {
    await navTo(t, 'Settings', wait: 900);
    await c.snap('$s/05-settings-900', 'Settings at 900x600 (single column)');
  });
  await setWindow(1440, 900);
  await sleepPump(t, 800);
}
