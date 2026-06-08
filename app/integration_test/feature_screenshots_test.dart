// Captures screenshots of every major feature screen.
//
// Uses the Flutter render tree (no macOS Screen-Recording permission needed).
// Backs up user data before the run and restores it after.
//
// Run:
//   cd app && flutter test integration_test/feature_screenshots_test.dart -d macos
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/main.dart' as app;
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/storage_service.dart';

const _outDir = '/Users/thangnguyen/Projects/Personal/yourssh/screenshots';

// Screenshot folder groups
const _g1 = '$_outDir/01-terminal-ssh';
const _g2 = '$_outDir/02-sftp';
const _g3 = '$_outDir/03-port-forwarding';
const _g4 = '$_outDir/04-credentials-security';
const _g5 = '$_outDir/05-settings';
const _g6 = '$_outDir/06-plugins';
const _g9 = '$_outDir/09-recording';

Future<void> _snap(WidgetTester tester, String path) async {
  await tester.pump(const Duration(milliseconds: 200));
  final view = RendererBinding.instance.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(
    Offset.zero & view.size,
    pixelRatio: view.flutterView.devicePixelRatio,
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SNAP: $path');
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 20),
  String what = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('timed out: $what');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Tap a sidebar nav item by its label text.
Future<void> _navTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture feature screenshots', (tester) async {
    // Create output directories
    for (final d in [_g1, _g2, _g3, _g4, _g5, _g6, _g9]) {
      Directory(d).createSync(recursive: true);
    }

    final prefs = await SharedPreferences.getInstance();
    final backupHosts = prefs.getString('yourssh.hosts');
    final backupKnown = prefs.getString('yourssh.known_hosts');
    final backupWorkspace = prefs.getString('workspace_snapshot');
    final backupUpdateCheck = prefs.getInt('last_update_check');
    final backupPortForwards = prefs.getString('yourssh.port_forwards');

    final storage = StorageService();

    // Seed demo hosts
    final demoHosts = [
      Host(
        id: 'demo-web-server',
        label: 'Web Server',
        host: 'web.example.com',
        port: 22,
        username: 'deploy',
        authType: AuthType.privateKey,
      ),
      Host(
        id: 'demo-db-server',
        label: 'Database',
        host: 'db.internal',
        port: 22,
        username: 'admin',
        authType: AuthType.password,
      ),
      Host(
        id: 'demo-bastion',
        label: 'Bastion Host',
        host: 'bastion.company.com',
        port: 22,
        username: 'ops',
        authType: AuthType.agent,
      ),
      Host(
        id: 'demo-dev',
        label: 'Dev Machine',
        host: '192.168.1.50',
        port: 22,
        username: 'dev',
        authType: AuthType.privateKey,
      ),
      Host(
        id: 'demo-rdp',
        label: 'Windows Desktop',
        host: '10.0.0.10',
        port: 3389,
        username: 'Administrator',
        authType: AuthType.password,
        protocol: HostProtocol.rdp,
        rdpSecurity: RdpSecurityMode.nla,
      ),
    ];

    // Seed port forwards
    const portForwardsJson = '''[
      {"id":"pf-mysql","hostId":"demo-db-server","type":"local","localPort":3307,"remoteHost":"127.0.0.1","remotePort":3306,"label":"MySQL Tunnel","enabled":true},
      {"id":"pf-redis","hostId":"demo-web-server","type":"local","localPort":6379,"remoteHost":"127.0.0.1","remotePort":6379,"label":"Redis Tunnel","enabled":true},
      {"id":"pf-socks","hostId":"demo-bastion","type":"dynamic","localPort":1080,"remoteHost":"","remotePort":0,"label":"SOCKS5 Proxy","enabled":false}
    ]''';

    try {
      await storage.saveHosts(demoHosts);
      await storage.saveKnownHosts([]);
      await prefs.remove('workspace_snapshot');
      await prefs.setInt('last_update_check', DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('yourssh.port_forwards', portForwardsJson);

      // ── Launch app ───────────────────────────────────────────────────────
      app.main();
      await tester.pump(const Duration(seconds: 2));
      await _waitFor(
        tester,
        () => find.text('Web Server').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        what: 'dashboard with seeded hosts',
      );

      // ── 1. TERMINAL & SSH ────────────────────────────────────────────────

      // 1a. Hosts dashboard
      await _snap(tester, '$_g1/01-hosts-dashboard.png');

      // 1b. NEW HOST panel open (SSH mode)
      await tester.tap(find.text('NEW HOST').first);
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g1/02-new-host-panel-ssh.png');

      // 1c. Host editor with data filled in (edit the first SSH host)
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump(const Duration(milliseconds: 300));
      // Long-press on "Web Server" card to open context menu, then Edit
      await tester.longPress(find.text('Web Server').first);
      await tester.pump(const Duration(milliseconds: 400));
      // Try tapping Edit in the context menu
      final editFinder = find.text('Edit');
      if (editFinder.evaluate().isNotEmpty) {
        await tester.tap(editFinder.first);
        await tester.pump(const Duration(milliseconds: 500));
        await _snap(tester, '$_g1/03-host-editor-filled.png');
        // Close panel
        await tester.tap(find.byIcon(Icons.close).first);
        await tester.pump(const Duration(milliseconds: 300));
      }

      // ── 2. SFTP ──────────────────────────────────────────────────────────
      await _navTo(tester, 'SFTP');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g2/01-sftp-browser.png');

      // ── 3. PORT FORWARDING ───────────────────────────────────────────────
      await _navTo(tester, 'Port Forwarding');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g3/01-port-forward-rules.png');

      // Open the "Add Rule" panel if available
      final addRuleFinder = find.text('ADD RULE');
      if (addRuleFinder.evaluate().isNotEmpty) {
        await tester.tap(addRuleFinder.first);
        await tester.pump(const Duration(milliseconds: 500));
        await _snap(tester, '$_g3/02-add-rule-panel.png');
        final closeFinder = find.byIcon(Icons.close);
        if (closeFinder.evaluate().isNotEmpty) {
          await tester.tap(closeFinder.first);
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      // ── 4. CREDENTIALS & SECURITY ────────────────────────────────────────

      // 4a. Keychain
      await _navTo(tester, 'Keychain');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g4/01-keychain.png');

      // 4b. Known Hosts
      await _navTo(tester, 'Known Hosts');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g4/02-known-hosts.png');

      // ── 5. SETTINGS ──────────────────────────────────────────────────────
      await _navTo(tester, 'Settings');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g5/01-settings-general.png');

      // Scroll to show Terminal section
      final scrollFinder = find.byType(SingleChildScrollView);
      if (scrollFinder.evaluate().isNotEmpty) {
        await tester.drag(scrollFinder.first, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 300));
        await _snap(tester, '$_g5/02-settings-terminal.png');

        // Scroll more to show Sync section
        await tester.drag(scrollFinder.first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
        await _snap(tester, '$_g5/03-settings-sync.png');

        // Scroll more to show Updates section
        await tester.drag(scrollFinder.first, const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 300));
        await _snap(tester, '$_g5/04-settings-updates.png');
      }

      // ── 6. PLUGINS ───────────────────────────────────────────────────────
      await _navTo(tester, 'Plugins');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g6/01-plugins.png');

      // ── 9. RECORDING ─────────────────────────────────────────────────────
      await _navTo(tester, 'Recordings');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_g9/01-recording-library.png');

      // ── Audit Log ────────────────────────────────────────────────────────
      await _navTo(tester, 'Audit Log');
      await tester.pump(const Duration(milliseconds: 500));
      await _snap(tester, '$_outDir/audit-log.png');

      // ── Back to Hosts — dashboard with RDP badge visible ─────────────────
      await _navTo(tester, 'Hosts');
      await tester.pump(const Duration(milliseconds: 400));
      await _snap(tester, '$_g1/04-dashboard-with-rdp-badge.png');

    } finally {
      // Restore user data
      if (backupHosts != null) {
        await prefs.setString('yourssh.hosts', backupHosts);
      } else {
        await prefs.remove('yourssh.hosts');
      }
      if (backupKnown != null) {
        await prefs.setString('yourssh.known_hosts', backupKnown);
      } else {
        await prefs.remove('yourssh.known_hosts');
      }
      if (backupWorkspace != null) {
        await prefs.setString('workspace_snapshot', backupWorkspace);
      } else {
        await prefs.remove('workspace_snapshot');
      }
      if (backupUpdateCheck != null) {
        await prefs.setInt('last_update_check', backupUpdateCheck);
      } else {
        await prefs.remove('last_update_check');
      }
      if (backupPortForwards != null) {
        await prefs.setString('yourssh.port_forwards', backupPortForwards);
      } else {
        await prefs.remove('yourssh.port_forwards');
      }
    }
  });
}
