// 01 first launch: empty dashboard, bell, command palette.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show FSwitch;
import 'nav.dart';
import 'sections.dart';

const s = '01-first-launch';

Future<void> runFirstLaunch(JourneyContext c) async {
  final t = c.t;
  await setWindow(1440, 900);
  await sleepPump(t, 1200);
  await c.snap('$s/01-empty-dashboard', 'First launch: empty dashboard with the "No hosts yet" empty state and the toolbar (search, sort, grid/list, Discover, Select, Local terminal, New host)');
  await step(c.notes, 'bell', () async {
    await tapTooltip(t, 'Notifications', wait: 600);
    await c.snap('$s/02-notifications-empty', 'Notification bell opened with no notifications');
    await pressEscape(t);
    await tapText(t, 'Hosts', index: 0, wait: 300);
  });
  await step(c.notes, 'palette', () async {
    await key(t, LogicalKeyboardKey.keyK, meta: true);
    await sleepPump(t, 500);
    await c.snap('$s/03-command-palette', 'Command palette (Cmd+K) open');
    await pressEscape(t);
  });
  await step(c.notes, 'plugins', () async {
    await navTo(t, 'Plugins');
    await c.snap('$s/04-plugins-default', 'Plugin manager on a fresh install: built-in plugins (Snippets, DevOps, Web Tools) are off by default; script plugins list');
    final sw = find.byType(FSwitch);
    final n = sw.evaluate().length;
    for (var i = 0; i < n; i++) {
      await t.tap(find.byType(FSwitch).at(i), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 500));
    }
    await sleepPump(t, 800);
    await c.snap('$s/05-plugins-enabled', 'All built-in plugins switched on (they then appear in the sidebar / terminal toolbar)');
    await navTo(t, 'Hosts');
  });
}
