// Captures screenshots of every mobile (Android) screen.
//
// Runs the real app on a device/emulator and captures the actual device surface,
// so the shots are exactly what the phone draws. The frames travel back over the
// driver connection and test_driver/integration_test.dart writes them to
// screenshots/11-mobile/ on the host — `flutter test` would uninstall the app and
// delete anything written inside it.
//
// Prereqs:
//   1. An Android emulator or device: `flutter emulators --launch <id>`
//   2. A local SSH server for the terminal / SFTP shots, reachable from the
//      emulator as 10.0.2.2:2222:
//        docker run -d --name yourssh-ssh-demo -p 2222:2222 \
//          -e PASSWORD_ACCESS=true -e USER_NAME=demo -e USER_PASSWORD=demo1234 \
//          lscr.io/linuxserver/openssh-server:latest
//      Without it the terminal shot shows the failure state instead.
//
// Run:
//   cd app && flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/mobile_screenshots_test.dart -d emulator-5554
//
// Seeds demo hosts / keys / snippets into prefs and restores whatever was there
// in a finally block.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh/main.dart' as app;
import 'package:yourssh/models/host.dart';
import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/storage_service.dart';

/// The demo SSH server, as seen from inside the emulator.
const _demoHostAddr = '10.0.2.2';
const _demoPort = 2222;
const _demoUser = 'demo';
const _demoPassword = 'demo1234';

late IntegrationTestWidgetsFlutterBinding _binding;
const _shotDir = 'screenshots/11-mobile';
int _seq = 0;

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 350));
  _seq++;
  final id = '$_shotDir/${_seq.toString().padLeft(2, '0')}-$name';
  await _binding.takeScreenshot(id);
  // ignore: avoid_print
  print('SNAP: $id');
}

/// Pump until [cond] holds. Screens here wait on real network work, so a plain
/// pumpAndSettle would either return too early or spin forever on animations.
Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) return false;
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 200));
  return true;
}

/// Every Text on screen — printed when a wait times out, so a failed run says
/// where the app actually was instead of just which label was missing.
List<String> _visibleText() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .toList();

Future<void> _tapText(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Pop through the root navigator — the contextual screens are pushed there, so
/// a Scaffold-derived context can land on the wrong navigator. [until] names a
/// label that must reappear before we carry on.
Future<void> _back(WidgetTester tester, {String? until}) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pump(const Duration(milliseconds: 700));
  if (until != null) {
    final ok = await _waitFor(
        tester, () => find.text(until).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10));
    if (!ok) throw StateError('after pop, never saw "$until"');
  }
}

List<Host> _demoHosts() => [
      Host(
        label: 'demo-server',
        host: _demoHostAddr,
        port: _demoPort,
        username: _demoUser,
        group: 'Lab',
        tags: const ['docker', 'local'],
        detectedOs: 'alpine',
      ),
      Host(
        label: 'prod-web-01',
        host: '203.0.113.10',
        username: 'deploy',
        group: 'Production',
        tags: const ['nginx', 'edge'],
        detectedOs: 'ubuntu',
      ),
      Host(
        label: 'staging-db',
        host: '198.51.100.24',
        username: 'postgres',
        group: 'Staging',
        tags: const ['postgres'],
        detectedOs: 'debian',
      ),
      Host(
        label: 'raspberry-pi',
        host: '192.168.1.50',
        username: 'pi',
        group: 'Home',
        tags: const ['arm'],
        detectedOs: 'raspbian',
      ),
    ];

List<SshKeyEntry> _demoKeys() => [
      SshKeyEntry(
        label: 'id_ed25519 (laptop)',
        algorithm: KeyAlgorithm.ed25519,
        publicKey:
            'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKp3Xk9DemoOnlyNotARealKeyAAAA thang@laptop',
        privateKeyPath: '/sdcard/Documents/YourSSH/keys/id_ed25519',
      ),
      SshKeyEntry(
        label: 'deploy-rsa',
        algorithm: KeyAlgorithm.rsa,
        publicKey:
            'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDemoOnlyNotARealKeyAAAAAAAA deploy@ci',
        privateKeyPath: '/sdcard/Documents/YourSSH/keys/deploy_rsa',
      ),
    ];

List<Snippet> _demoSnippets() => [
      Snippet(
        label: 'Disk usage',
        command: 'df -h | sort -k5 -r | head -20',
        description: 'Largest filesystems first',
        tag: 'system',
      ),
      Snippet(
        label: 'Top memory',
        command: 'ps aux --sort=-%mem | head -15',
        description: 'Heaviest processes by RSS',
        tag: 'system',
      ),
      Snippet(
        label: 'Tail nginx errors',
        command: 'tail -f /var/log/nginx/error.log',
        description: 'Follow the error log',
        tag: 'nginx',
      ),
      Snippet(
        label: 'Docker cleanup',
        command: 'docker system prune -af --volumes',
        description: 'Reclaim disk on a build box',
        tag: 'docker',
      ),
    ];

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture mobile screenshots', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final backup = {
      for (final k in const [
        'yourssh.hosts',
        'yourssh.keys',
        'yourssh.snippets',
        'yourssh.port_forwards',
      ])
        k: prefs.getString(k),
    };
    final backupLock = prefs.getBool('app_lock_enabled');

    try {
      final hosts = _demoHosts();
      await prefs.setString(
          'yourssh.hosts', jsonEncode(hosts.map((h) => h.toJson()).toList()));
      await prefs.setString('yourssh.keys',
          jsonEncode(_demoKeys().map((k) => k.toJson()).toList()));
      await prefs.setString('yourssh.snippets',
          jsonEncode(_demoSnippets().map((s) => s.toJson()).toList()));
      // Biometric lock would block the whole run on an emulator with no
      // enrolled fingerprint.
      await prefs.setBool('app_lock_enabled', false);
      // Keep the update banner out of the shots.
      await prefs.setInt(
          'last_update_check', DateTime.now().millisecondsSinceEpoch);
      // The demo host authenticates with a password, so it has to be in secure
      // storage before the app connects.
      await StorageService().savePassword(hosts.first.id, _demoPassword);

      app.main();
      await tester.pump(const Duration(seconds: 3));
      // Android renders into a SurfaceView the test process cannot read; this
      // swaps it for an offscreen-image surface takeScreenshot can capture.
      await _binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 500));
      await _waitFor(tester, () => find.text('demo-server').evaluate().isNotEmpty);

      // ── Hosts ────────────────────────────────────────────────────────────
      await _snap(tester, 'hosts-list');

      // Long-press opens the per-host action sheet (Edit / Delete).
      await tester.longPress(find.text('prod-web-01').first);
      await tester.pump(const Duration(milliseconds: 700));
      await _snap(tester, 'host-actions');
      await _back(tester, until: 'demo-server');

      // ── Add host (the FAB, which is a bare + icon) ────────────────────────
      await tester.tap(find.byIcon(Icons.add).first);
      await _waitFor(tester, () => find.text('New host').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 10));
      await _snap(tester, 'add-host');
      await _back(tester, until: 'demo-server');

      // ── Snippets / Keys / Settings tabs ──────────────────────────────────
      await _tapText(tester, 'Snippets');
      await _snap(tester, 'snippets');

      await _tapText(tester, 'Keys');
      await _snap(tester, 'keys');

      await _tapText(tester, 'Settings');
      await _snap(tester, 'settings');

      // Sync screen lives behind the Supabase row.
      await _tapText(tester, 'Supabase sync');
      await _snap(tester, 'sync-pairing');
      await _back(tester, until: 'Supabase sync');

      // ── Terminal against the real SSH server ─────────────────────────────
      await _tapText(tester, 'Hosts');
      await tester.tap(find.ancestor(
              of: find.text('demo-server'), matching: find.byType(HostCard))
          .first);
      // Connecting hits the network: hold until the terminal screen is up.
      await tester.pump(const Duration(seconds: 2));
      await _snap(tester, 'terminal-connecting');
      final connected = await _waitFor(
        tester,
        () => find.byType(MobileTerminalScreen).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
      );
      if (!connected) {
        // ignore: avoid_print
        print('DIAG: no terminal. on screen: ${_visibleText()}');
      } else {
        // Report the live session state so a shot of a failed shell is obvious
        // in the log rather than a mystery in the PNG.
        final ctx = tester.element(find.byType(MobileTerminalScreen));
        for (final s in Provider.of<SessionProvider>(ctx, listen: false).sshSessions) {
          // ignore: avoid_print
          print('DIAG session ${s.host.label}: status=${s.status} err=${s.errorMessage}');
        }
      }
      // Let the shell draw its prompt / motd.
      await tester.pump(const Duration(seconds: 3));
      await _snap(tester, 'terminal-session');

      if (connected) {
        // Drive real commands through the terminal so the shot shows output
        // instead of a bare prompt. textInput() goes out over the SSH channel
        // exactly like a keypress does.
        final ctx = tester.element(find.byType(MobileTerminalScreen));
        final session =
            Provider.of<SessionProvider>(ctx, listen: false).sshSessions.last;
        for (final cmd in const ['uname -a', 'ls -la /etc | head -8']) {
          session.terminal.textInput('$cmd\r');
          await tester.pump(const Duration(milliseconds: 1200));
        }
        await tester.pump(const Duration(seconds: 1));
        await _snap(tester, 'terminal-accessory-bar');

        // ⋮ menu → Files (SFTP) and Port forwarding
        final more = find.byIcon(Icons.more_vert);
        if (more.evaluate().isNotEmpty) {
          await tester.tap(more.first);
          await tester.pump(const Duration(milliseconds: 700));
          await _snap(tester, 'terminal-menu');

          if (find.text('Files').evaluate().isNotEmpty) {
            await _tapText(tester, 'Files');
            await _waitFor(tester, () => find.text('Refresh').evaluate().isNotEmpty,
                timeout: const Duration(seconds: 20));
            await tester.pump(const Duration(seconds: 2));
            await _snap(tester, 'sftp-browser');
            await _back(tester);
          }

          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pump(const Duration(milliseconds: 700));
          if (find.text('Port forwarding').evaluate().isNotEmpty) {
            await _tapText(tester, 'Port forwarding');
            await tester.pump(const Duration(seconds: 1));
            await _snap(tester, 'port-forwarding');
            if (find.text('Add rule').evaluate().isNotEmpty) {
              await _tapText(tester, 'Add rule');
              await _snap(tester, 'port-forward-add');
              await _back(tester);
            }
            await _back(tester);
          }
        }
      }
      await _snap(tester, 'terminal-final');
    } finally {
      for (final entry in backup.entries) {
        if (entry.value == null) {
          await prefs.remove(entry.key);
        } else {
          await prefs.setString(entry.key, entry.value!);
        }
      }
      if (backupLock == null) {
        await prefs.remove('app_lock_enabled');
      } else {
        await prefs.setBool('app_lock_enabled', backupLock);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
