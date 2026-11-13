// 15 plugins: manager, JS plugin console, plugin panel.
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '15-plugins';

Future<void> runPlugins(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Plugins', wait: 900);
  await c.snap('$s/01-manager', 'Plugin manager: built-in plugins enabled, script plugins loaded from ~/.yourssh/plugins');
  c.notes.add('15: no script (JS) plugin is listed in the manager on a fresh demo home, so the per-plugin console (View logs) could not be shown.');
  await step(c.notes, 'snippets panel', () async {
    await navTo(t, 'Snippets', wait: 1200);
    await c.snap('$s/03-snippets-screen', 'Snippets plugin screen from the sidebar');
  });
}
