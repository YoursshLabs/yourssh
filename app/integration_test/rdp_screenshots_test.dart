// Screenshot capture for the in-app RDP client (incl. fullscreen).
//
// Drives the REAL app against a local xrdp container and saves PNGs of each
// feature state into <repo>/screenshots/. Taps are synthesized inside
// Flutter and frames are captured from the render tree, so no macOS
// Screen-Recording/Accessibility permissions are needed.
//
// Prereqs:
//   docker run -d --name yourssh-rdp-demo -p 3389:3389 \
//     scottyhardy/docker-remote-desktop:latest
//   docker exec yourssh-rdp-demo bash -c \
//     "useradd -m -s /bin/bash demo; echo 'demo:demo12345' | chpasswd"
//
// Run:
//   cd app && flutter test integration_test/rdp_screenshots_test.dart -d macos
//
// The user's real prefs (hosts, known hosts, workspace) are backed up before
// the run and restored afterwards.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/main.dart' as app;
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

const _outDir = '/Users/thangnguyen/Projects/Personal/yourssh/screenshots';
const _demoHostId = 'screenshot-rdp-demo';

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 120));
  final view = RendererBinding.instance.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(
    Offset.zero & view.size,
    pixelRatio: view.flutterView.devicePixelRatio,
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$_outDir/$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SNAP saved: ${file.path}');
}

/// Real-time poll: integration pumps honor wall-clock durations.
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 90),
  String what = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('timed out waiting for $what');
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture RDP feature screenshots', (tester) async {
    Directory(_outDir).createSync(recursive: true);

    // ── Backup user data, seed the demo host ────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final backupHosts = prefs.getString('hosts');
    final backupKnown = prefs.getString('known_hosts');
    final backupWorkspace = prefs.getString('workspace_snapshot');
    final backupUpdateCheck = prefs.getInt('last_update_check');

    final storage = StorageService();
    final demoHost = Host(
      id: _demoHostId,
      label: 'Demo Desktop',
      host: '127.0.0.1',
      port: 3389,
      username: 'demo',
      authType: AuthType.password,
      protocol: HostProtocol.rdp,
      rdpSecurity: RdpSecurityMode.auto,
    );

    try {
      await storage.saveHosts([demoHost]);
      await storage.savePassword(_demoHostId, 'demo12345');
      await storage.saveKnownHosts([]); // force the TOFU dialog
      await prefs.remove('workspace_snapshot'); // no auto-restore noise
      // Debounce the GitHub update check so no banner pollutes the shots.
      await prefs.setInt(
          'last_update_check', DateTime.now().millisecondsSinceEpoch);

      // ── Launch the real app ────────────────────────────────────────────
      // main() is `void` (async internally) — give it real time to finish
      // window setup + provider wiring and render the first frames.
      app.main();
      await tester.pump(const Duration(seconds: 2));
      await _waitFor(
        tester,
        () => find.text('Demo Desktop').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        what: 'dashboard with seeded host',
      );

      // 1. Hosts dashboard with the RDP badge.
      expect(find.text('Demo Desktop'), findsWidgets);
      await _snap(tester, '01-dashboard-rdp-badge');

      // 2. Host editor in RDP mode (protocol selector + RDP-only fields).
      // Scope finds to the panel — the dashboard card's RDP badge shares the
      // 'RDP' text and other widgets share the close icon.
      await tester.ensureVisible(find.text('NEW HOST').first);
      await tester.tap(find.text('NEW HOST').first);
      await tester.pump(const Duration(milliseconds: 400));
      final panel = find.byType(HostDetailPanel);
      await tester.tap(find.descendant(
          of: find.byType(SegmentedButton<HostProtocol>),
          matching: find.text('RDP')));
      await tester.pump(const Duration(milliseconds: 400));
      await _snap(tester, '02-host-editor-rdp-form');
      // Close the panel via its header X.
      await tester.tap(
          find.descendant(of: panel, matching: find.byIcon(Icons.close)).first);
      await tester.pump(const Duration(milliseconds: 400));

      // 3. Connect (double-tap the card) → TOFU certificate dialog.
      await tester.tap(find.text('Demo Desktop').first);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Demo Desktop').first);
      await _waitFor(
        tester,
        () => find.text('Trust RDP certificate?').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
        what: 'TOFU dialog',
      );
      await _snap(tester, '03-tofu-certificate-dialog');

      // Accept → session proceeds to connected.
      await tester.tap(find.text('Accept'));
      final ctx = tester.element(find.byType(MaterialApp).first);
      final sessions = Provider.of<SessionProvider>(ctx, listen: false);
      RdpSession rdp() =>
          sessions.sessions.whereType<RdpSession>().first;
      await _waitFor(
        tester,
        () =>
            sessions.sessions.whereType<RdpSession>().isNotEmpty &&
            rdp().status == RdpSessionStatus.connected,
        what: 'RDP connected',
      );
      // Wait for the first real desktop frames (xfce session spin-up).
      await _waitFor(
        tester,
        () => rdp().image != null,
        what: 'first RDP frame',
      );
      await tester.pump(const Duration(seconds: 6)); // let the desktop settle
      await _snap(tester, '04-rdp-workspace-connected');

      // 4. Fullscreen: toolbar button → OS fullscreen, chrome collapses,
      //    pill flashes for 2.5 s.
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pump(const Duration(milliseconds: 1500)); // window anim
      await _snap(tester, '05-fullscreen-with-pill');

      // Pill auto-hides → clean fullscreen desktop.
      await tester.pump(const Duration(seconds: 3));
      await _snap(tester, '06-fullscreen-clean');

      // Hover the top edge → pill reveals again.
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      final topCenter = Offset(
          RendererBinding.instance.renderViews.first.size.width / 2, 3);
      await g.moveTo(topCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await _snap(tester, '07-fullscreen-hover-reveal');
      await g.removePointer();

      // 5. Exit fullscreen via the pill → back to windowed chrome.
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump(const Duration(milliseconds: 1500)); // window anim
      await _snap(tester, '08-back-to-windowed');

      // Tear the session down so the container side closes cleanly.
      sessions.closeSession(rdp().id);
      await tester.pump(const Duration(seconds: 1));
    } finally {
      // ── Restore the user's real data ───────────────────────────────────
      if (backupHosts != null) {
        await prefs.setString('hosts', backupHosts);
      } else {
        await prefs.remove('hosts');
      }
      if (backupKnown != null) {
        await prefs.setString('known_hosts', backupKnown);
      } else {
        await prefs.remove('known_hosts');
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
      await storage.deletePassword(_demoHostId);
    }
  });
}
