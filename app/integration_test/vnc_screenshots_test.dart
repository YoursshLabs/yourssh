// Screenshot capture for the in-app VNC client (incl. fullscreen).
//
// Drives the REAL app against a local x11vnc/TigerVNC container and saves PNGs
// into <repo>/screenshots/. Frames are captured from the render tree, so no
// macOS Screen-Recording permission is needed.
//
// Prereqs (a password-auth VNC server on :5900, password "demo12345"):
//   docker run -d --name yourssh-vnc-demo -p 5900:5900 \
//     -e VNC_PW=demo12345 dorowu/ubuntu-desktop-lxde-vnc:latest
//   (or any x11vnc/TigerVNC server with password "demo12345" on 5900)
//
// Run:
//   cd app && flutter test integration_test/vnc_screenshots_test.dart -d macos
//
// The user's real prefs are backed up before the run and restored afterwards.
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
import 'package:yourssh/models/vnc_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

const _outDir = '/Users/thangnguyen/Projects/Personal/yourssh/screenshots';
const _demoHostId = 'screenshot-vnc-demo';

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

  testWidgets('capture VNC feature screenshots', (tester) async {
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
      label: 'Demo VNC',
      host: '127.0.0.1',
      port: 5900,
      username: '',
      authType: AuthType.password,
      protocol: HostProtocol.vnc,
    );

    try {
      await storage.saveHosts([demoHost]);
      await storage.savePassword(_demoHostId, 'demo12345');
      await prefs.remove('workspace_snapshot'); // no auto-restore noise
      // Debounce the GitHub update check so no banner pollutes the shots.
      await prefs.setInt(
          'last_update_check', DateTime.now().millisecondsSinceEpoch);

      // ── Launch the real app ────────────────────────────────────────────
      // main() is `void` (async internally) — give it real time to finish
      // window setup + provider wiring and render the first frames.
      app.main(const <String>[]);
      await tester.pump(const Duration(seconds: 2));
      await _waitFor(
        tester,
        () => find.text('Demo VNC').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
        what: 'dashboard with seeded host',
      );

      // 1. Hosts dashboard with the VNC badge.
      expect(find.text('Demo VNC'), findsWidgets);
      await _snap(tester, '01-dashboard-vnc-badge');

      // 2. Host editor in VNC mode (protocol selector + VNC fields).
      // Scope finds to the panel — the dashboard card's VNC badge shares the
      // 'VNC' text and other widgets share the close icon.
      await tester.ensureVisible(find.text('New host').first);
      await tester.tap(find.text('New host').first);
      await tester.pump(const Duration(milliseconds: 400));
      final panel = find.byType(HostDetailPanel);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('host-protocol-tabs')),
          matching: find.text('VNC')));
      await tester.pump(const Duration(milliseconds: 400));
      await _snap(tester, '02-host-editor-vnc-form');
      // Close the panel via its header X.
      await tester.tap(
          find.descendant(of: panel, matching: find.byTooltip('Close')).first);
      await tester.pump(const Duration(milliseconds: 400));

      // 3. Connect (double-tap the card) → VNC has no TOFU/cert dialog;
      //    go straight to waiting for connected.
      await tester.tap(find.text('Demo VNC').first);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('Demo VNC').first);
      final ctx = tester.element(find.byType(MaterialApp).first);
      final sessions = Provider.of<SessionProvider>(ctx, listen: false);
      VncSession vnc() => sessions.sessions.whereType<VncSession>().first;
      await _waitFor(
        tester,
        () =>
            sessions.sessions.whereType<VncSession>().isNotEmpty &&
            vnc().status == VncSessionStatus.connected,
        what: 'VNC connected',
      );
      // Wait for the first real desktop frame.
      await _waitFor(tester, () => vnc().image != null, what: 'first VNC frame');
      await tester.pump(const Duration(seconds: 4)); // let the desktop settle
      await _snap(tester, '03-vnc-workspace-connected');

      // 4. Fullscreen: toolbar button → OS fullscreen, chrome collapses,
      //    pill flashes for 2.5 s.
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pump(const Duration(milliseconds: 1500)); // window anim
      await _snap(tester, '04-fullscreen-with-pill');

      // Pill auto-hides → clean fullscreen desktop.
      await tester.pump(const Duration(seconds: 3));

      // Hover the top edge → pill reveals again.
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      final topCenter = Offset(
          RendererBinding.instance.renderViews.first.size.width / 2, 3);
      await g.moveTo(topCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await _snap(tester, '05-fullscreen-hover-reveal');
      await g.removePointer();

      // 5. Exit fullscreen via the pill → back to windowed chrome.
      await tester.tap(find.text('Exit fullscreen'));
      await tester.pump(const Duration(milliseconds: 1500)); // window anim
      await _snap(tester, '06-back-to-windowed');

      // Tear the session down so the container side closes cleanly.
      sessions.closeSession(vnc().id);
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
