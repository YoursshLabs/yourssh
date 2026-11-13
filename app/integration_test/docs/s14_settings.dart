// 14 settings: every section, hotkeys screen, sync dialogs.
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'nav.dart';
import 'sections.dart';

const s = '14-settings';

Future<void> runSettings(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Settings', wait: 900);
  await c.snap('$s/01-settings-top', 'Settings page (first section: Connection)');
  var n = 2;
  for (final (title, cap) in const [
    ('Appearance', 'Appearance: terminal theme, font size and font'),
    ('Terminal', 'Terminal: default shell, shell integration, tmux, TERM type, custom shells'),
    ('Keyword highlighting', 'Keyword highlighting rules (error / warning / success palettes)'),
    ('Recording', 'Recording: output folder, secret redaction'),
    ('Monitoring', 'Monitoring: keep-alive, network stats overlay'),
    ('Audit', 'Audit: retention and clear'),
    ('Security', 'Security: credential storage (Keychain) status'),
    ('Sync', 'Sync: Supabase cloud sync / LAN sync modes'),
    ('AI providers', 'AI providers: provider, model and API key (obscured)'),
    ('Keyboard', 'Keyboard: hotkey configuration entry'),
    ('Updates', 'Updates: version and check for updates'),
  ]) {
    await step(c.notes, 'settings $title', () async {
      var f = find.text(title);
      if (f.evaluate().isEmpty) f = find.text(title.toUpperCase());
      await scrollTo(t, f, alignment: 0.02);
      await c.snap('$s/${n.toString().padLeft(2, '0')}-${title.toLowerCase().replaceAll(' ', '-')}', cap);
    });
    n++;
  }
  await step(c.notes, 'hotkeys', () async {
    await scrollTo(t, byKeyStr('settings-hotkeys-configure'), alignment: 0.3);
    await tapKey(t, 'settings-hotkeys-configure', wait: 900);
    await c.snap('$s/14-hotkeys-screen', 'Hotkey configuration screen');
    await pressEscape(t);
    await tapTooltip(t, 'Back', wait: 600).catchError((_) {});
  });
  await step(c.notes, 'sync dialogs', () async {
    final sp = c.read<SyncProvider>();
    await sp.setSupabaseConfig('http://127.0.0.1:1', 'docs-demo-anon-key');
    await sleepPump(t, 800);
    await navTo(t, 'Plugins');
    await navTo(t, 'Settings', wait: 900);
    await scrollTo(t, find.text('Sync').first, alignment: 0.02);
    await c.snap('$s/15-sync-configured', 'Sync section after a Supabase project is configured (demo config pointing at localhost; no network)');
    await step(c.notes, 'p2p', () async {
      await tapText(t, 'P2P Transfer', wait: 800);
      await c.snap('$s/16-sync-p2p', 'Sync > P2P Transfer tab (LAN sync without a server)');
      if (byKeyStr('sync-show-qr').evaluate().isNotEmpty) {
        await tapKey(t, 'sync-show-qr', wait: 1800);
        await c.snap('$s/17-sync-qr-dialog', 'Show QR Code: LAN sync dialog (network interface choice, QR; this dialog is not dismissed by Esc, use Cancel)');
        await tapText(t, 'Cancel', wait: 700);
      }
      if (byKeyStr('sync-import-code').evaluate().isNotEmpty) {
        await tapKey(t, 'sync-import-code', wait: 900);
        await c.snap('$s/18-sync-import-dialog', 'Import via Code dialog');
        await pressEscape(t);
        if (find.text('Cancel').evaluate().isNotEmpty) await tapText(t, 'Cancel', wait: 500);
      }
      await tapText(t, 'Cloud Sync', wait: 700);
    });
    await scrollTo(t, byKeyStr('sync-disconnect'), alignment: 0.4);
    await tapKey(t, 'sync-disconnect', wait: 800);
    await c.snap('$s/19-sync-disconnect-confirm', 'Disconnect sync? confirmation');
    await tapText(t, 'Cancel', wait: 500);
    await sp.clearSupabaseConfig();
    await sleepPump(t, 500);
  });
}
