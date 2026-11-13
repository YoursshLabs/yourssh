// 13 VNC.
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/vnc_session.dart';
import 'nav.dart';
import 'sections.dart';

const s = '13-vnc';

Future<void> runVnc(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Hosts');
  await tapText(t, 'New host', index: 0, wait: 800);
  await t.tap(find.descendant(of: byKeyStr('host-protocol-tabs'), matching: find.text('VNC')), warnIfMissed: false);
  await sleepPump(t, 600);
  await c.snap('$s/01-editor-vnc-mode', 'Host editor in VNC mode: port 5900, password, clipboard, SSH tunnel');
  await typeKey(t, 'host-label-field', 'Demo VNC');
  await typeKey(t, 'host-address-field', '127.0.0.1');
  await step(c.notes, 'vnc user', () => typeKey(t, 'host-username-field', 'demo'));
  await typeKey(t, 'host-password-field', 'demo12345');
  await tapKey(t, 'host-save-button', wait: 900);
  await sleepPump(t, 500);
  await c.snap('$s/02-dashboard-vnc-badge', 'Dashboard: the VNC host card carries a VNC badge');
  await doubleTap(t, find.text('Demo VNC').first);
  VncSession? vnc() => c.sessions.sessions.whereType<VncSession>().firstOrNull;
  await waitFor(t, () => vnc()?.status == VncSessionStatus.connected, seconds: 60, what: 'vnc connected');
  await waitFor(t, () => vnc()?.image != null, seconds: 60, what: 'first vnc frame');
  await sleepPump(t, 5000);
  await c.snap('$s/03-session-connected', 'VNC session: remote desktop with toolbar and status bar');
  await step(c.notes, 'close', () async {
    final v = vnc();
    if (v != null) c.sessions.closeSession(v.id);
    await sleepPump(t, 800);
  });
}
