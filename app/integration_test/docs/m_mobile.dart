// M1 mobile UI (YourSSHMobileApp) rendered in a phone-sized macOS window.
// The app is mounted by docs_journey_test.dart when DOCS_MODE=mobile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yourssh/mobile/mobile_app.dart';
import 'package:yourssh/mobile/screens/mobile_terminal_screen.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/mobile/widgets/mobile_fab.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'isolation.dart';
import 'nav.dart';
import 'sections.dart';

const s = 'M1-mobile';

Future<void> back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await t.pump(const Duration(milliseconds: 700));
}

Future<void> unlock(WidgetTester t) async {
  if (find.text('YourSSH is locked').evaluate().isNotEmpty) {
    await tapText(t, 'Unlock', wait: 1200);
  }
}

/// tapText that first dismisses the lock screen if the app re-locked.
Future<void> mtap(WidgetTester t, String label, {int wait = 600}) async {
  await unlock(t);
  await tapText(t, label, wait: wait);
}

/// The window can come up desktop-sized (observed after a desktop launch):
/// force the phone size and wait until the Flutter view really is 390 wide.
Future<void> ensurePhoneWindow(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    final w = t.view.physicalSize.width / t.view.devicePixelRatio;
    if (w > 380 && w < 420) return;
    await windowManager.setMinimumSize(const Size(300, 400));
    await windowManager.setSize(const Size(390, 876));
    await sleepPump(t, 700);
  }
  throw StateError('mobile window is not phone-sized: ${t.view.physicalSize}');
}

Future<void> runMobile(JourneyContext c) async {
  final t = c.t;
  await ensurePhoneWindow(t);
  // Lock gate (fake authenticator is still pending).
  await sleepPump(t, 1500);
  if (find.text('YourSSH is locked').evaluate().isNotEmpty) {
    await c.snap('$s/01-app-lock', 'App lock gate: "YourSSH is locked" with Unlock (biometric prompt is faked by the harness)');
    DocsLocalAuth.complete(true);
    await sleepPump(t, 1200);
    // The gate re-locks whenever the (unfocused) window reports an inactive
    // lifecycle state, which discards navigation state. Remount with the lock
    // switched off so the rest of the journey is stable.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock_enabled', false);
    runApp(const SizedBox.shrink());
    await sleepPump(t, 500);
    runApp(const YourSSHMobileApp());
    await sleepPump(t, 2500);
    await ensurePhoneWindow(t);
  } else {
    c.notes.add('M1: app-lock screen not shown');
  }
  await waitText(t, 'Demo Server', seconds: 20, throwOnTimeout: false);
  await c.snap('$s/02-hosts', 'Hosts tab: host cards with latency/status, groups and tags');
  await step(c.notes, 'host actions', () async {
    await unlock(t);
    await t.longPress(find.text('Bastion').first);
    await sleepPump(t, 800);
    await c.snap('$s/03-host-actions', 'Long-press a host: action sheet (Edit / Delete)');
    await back(t);
  });
  await step(c.notes, 'add host', () async {
    await unlock(t);
    await t.tap(find.byType(MobileFab).first, warnIfMissed: false);
    await waitText(t, 'New host', seconds: 10, throwOnTimeout: false);
    await sleepPump(t, 600);
    await c.snap('$s/04-add-host', 'Add host form (top)');
    final sc = find.byType(Scrollable);
    if (sc.evaluate().isNotEmpty) {
      await t.drag(sc.first, const Offset(0, -500));
      await sleepPump(t, 500);
      await c.snap('$s/05-add-host-scrolled', 'Add host form scrolled: authentication method, key, advanced options');
    }
    await back(t);
  });
  await step(c.notes, 'snippets', () async {
    await unlock(t);
    await mtap(t, 'Snippets', wait: 800);
    await c.snap('$s/06-snippets', 'Snippets tab');
  });
  await step(c.notes, 'keys', () async {
    await unlock(t);
    await mtap(t, 'Keys', wait: 800);
    await c.snap('$s/07-keys', 'Keys tab: imported key');
    if (find.text('Generate').evaluate().isNotEmpty) {
      await mtap(t, 'Generate', wait: 900);
      await c.snap('$s/08-key-generate', 'Generate key sheet');
      await pressEscape(t);
      if (find.text('Generate Key').evaluate().isNotEmpty) await back(t);
    }
  });
  await step(c.notes, 'settings', () async {
    await unlock(t);
    await mtap(t, 'Settings', wait: 800);
    await c.snap('$s/09-settings', 'Settings tab: Terminal, Security (biometric unlock, auto-lock), Keyboard & Sync');
    final sc = find.byType(Scrollable);
    if (find.text('Supabase sync').evaluate().isEmpty && sc.evaluate().isNotEmpty) {
      await t.drag(sc.first, const Offset(0, -400));
      await sleepPump(t, 500);
      await c.snap('$s/09b-settings-scrolled', 'Settings scrolled: Keyboard & Sync rows');
    }
    await mtap(t, 'Supabase sync', wait: 900);
    await c.snap('$s/10-sync', "Supabase sync / pair-device screen. The QR is generated by the screen itself and encodes the capture machine's real LAN address (cannot be faked): re-encode it before publishing");
    await back(t);
    if (find.text('Pair new device').evaluate().isNotEmpty) {
      c.notes.add('M1: "Pair new device" opens the camera QR scanner (mobile_scanner); skipped on macOS.');
    }
  });
  await step(c.notes, 'terminal', () async {
    await unlock(t);
    await mtap(t, 'Hosts', wait: 600);
    await t.tap(find.ancestor(of: find.text('Demo Server'), matching: find.byType(HostCard)).first, warnIfMissed: false);
    await sleepPump(t, 1500);
    await c.snap('$s/11-connecting', 'Connecting to the host', settleMs: 100);
    final ok = await waitFor(t, () => find.byType(MobileTerminalScreen).evaluate().isNotEmpty, seconds: 45, throwOnTimeout: false);
    if (!ok) throw StateError('no terminal screen: ${visibleText().take(30).toList()}');
    await sleepPump(t, 3000);
    final sess = c.sessions.sshSessions.last;
    await waitFor(t, () => sess.status == SessionStatus.connected, seconds: 30, throwOnTimeout: false);
    c.read<SshService>().sendInput(sess.id, 'ls -la\r');
    await sleepPump(t, 1500);
    await c.snap('$s/12-terminal', 'Terminal session with the shortcut accessory bar (Esc / Tab / Ctrl / arrows)');
    final more = find.byTooltip('More');
    stdoutTips();
    await step(c.notes, 'terminal menu', () async {
    await unlock(t);
      if (more.evaluate().isNotEmpty) {
        await t.tap(more.first, warnIfMissed: false);
        await sleepPump(t, 800);
        await c.snap('$s/13-terminal-menu', 'Terminal overflow menu: Files, Port forwarding, session list');
      }
    });
    await step(c.notes, 'sftp', () async {
    await unlock(t);
      await mtap(t, 'Files', wait: 2500);
      await sleepPump(t, 2000);
      await c.snap('$s/14-sftp', 'Mobile file browser (SFTP)');
      await back(t);
    });
    await step(c.notes, 'port forward', () async {
    await unlock(t);
      if (find.text('Port forwarding').evaluate().isEmpty) {
        await t.tap(find.byTooltip('More').first, warnIfMissed: false);
        await sleepPump(t, 700);
      }
      await mtap(t, 'Port forwarding', wait: 1000);
      await c.snap('$s/15-port-forwarding', 'Mobile port forwarding screen');
      if (find.text('Add forwarding rule').evaluate().isNotEmpty) {
        await mtap(t, 'Add forwarding rule', wait: 800);
        await c.snap('$s/16-port-forward-add', 'Add forwarding rule sheet');
        await back(t);
      }
      await back(t);
    });
    stdoutTips();
  });
}

void stdoutTips() => print('MOBILE TIPS: ${tooltips()} TEXT: ${visibleText().take(40).toList()}');
