// 12 RDP: editor in RDP mode, connect, cert trust dialog, session, fullscreen, disconnect.
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'nav.dart';
import 'sections.dart';

const s = '12-rdp';

Future<void> runRdp(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Hosts');
  await tapText(t, 'New host', index: 0, wait: 800);
  await t.tap(find.descendant(of: byKeyStr('host-protocol-tabs'), matching: find.text('RDP')), warnIfMissed: false);
  await sleepPump(t, 600);
  await c.snap('$s/01-editor-rdp-mode', 'Host editor in RDP mode: port flips to 3389, domain, RDP security, SSH tunnel, clipboard');
  await typeKey(t, 'host-label-field', 'Demo Desktop');
  await typeKey(t, 'host-address-field', '127.0.0.1');
  await typeKey(t, 'host-username-field', 'demo');
  await typeKey(t, 'host-password-field', 'demo12345');
  await step(c.notes, 'rdp sections', () async {
    await scrollTo(t, find.text('RDP SECURITY'), alignment: 0.1);
    await c.snap('$s/02-rdp-security', 'RDP-only options: security mode (Auto / NLA / TLS), clipboard, SSH tunnel');
  });
  await scrollTo(t, byKeyStr('host-label-field'), alignment: 0.0);
  await c.snap('$s/03-editor-filled', 'RDP host filled in');
  await tapKey(t, 'host-save-button', wait: 900);
  await sleepPump(t, 500);
  await c.snap('$s/04-dashboard-rdp-badge', 'Dashboard: the RDP host card carries an RDP badge');
  await doubleTap(t, find.text('Demo Desktop').first);
  final got = await waitText(t, 'Trust RDP certificate?', seconds: 40, throwOnTimeout: false);
  if (!got) {
    c.notes.add('RDP: no certificate dialog within 40 s (server not ready?). Visible: ${visibleText().take(30).toList()}');
    return;
  }
  await c.snap('$s/05-cert-trust-dialog', 'First connect: "Trust RDP certificate?" dialog with the SHA-256 fingerprint');
  await tapText(t, 'Accept', wait: 800);
  RdpSession? rdp() => c.sessions.sessions.whereType<RdpSession>().firstOrNull;
  await waitFor(t, () => rdp()?.status == RdpSessionStatus.connected, seconds: 90, what: 'rdp connected');
  await waitFor(t, () => rdp()?.image != null, seconds: 90, what: 'first rdp frame');
  await sleepPump(t, 7000);
  await c.snap('$s/06-session-connected', 'RDP session: remote desktop, toolbar, status bar');
  await step(c.notes, 'toolbar hover', () async {
    await hoverOn(t, find.byTooltip('Fullscreen'));
    await c.snap('$s/07-toolbar-tooltip', 'RDP toolbar: Fullscreen / Send Ctrl+Alt+Del / clipboard / disconnect');
  });
  await step(c.notes, 'fullscreen', () async {
    await tapTooltip(t, 'Fullscreen', wait: 1800);
    await c.snap('$s/08-fullscreen-pill', 'Fullscreen: chrome collapses, exit pill flashes at the top edge');
    await sleepPump(t, 3500);
    await c.snap('$s/09-fullscreen-clean', 'Fullscreen after the pill auto-hides');
    await mouseMove(t, const Offset(400, 300));
    await mouseMove(t, Offset(RendererBinding.instance.renderViews.first.size.width / 2, 3));
    await sleepPump(t, 300);
    await c.snap('$s/10-fullscreen-hover-pill', 'Hovering the top edge reveals the exit-fullscreen pill');
    await tapTooltip(t, 'Exit fullscreen', wait: 1800);
    await c.snap('$s/11-back-windowed', 'Back to windowed mode');
  });
  await step(c.notes, 'disconnect', () async {
    await tapTooltip(t, 'Disconnect', wait: 1500);
    await c.snap('$s/12-disconnected', 'After Disconnect: session ended state');
    final r = rdp();
    if (r != null) c.sessions.closeSession(r.id);
  });
}
