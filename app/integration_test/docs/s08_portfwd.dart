// 08 port forwarding.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '08-port-forwarding';
Socket? _probe;

Future<void> runPortForward(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Port Forwarding');
  await c.snap('$s/01-empty', 'Port forwarding with no rules');
  await tapText(t, '+ New Rule', wait: 700);
  await c.snap('$s/02-new-rule-panel', 'New rule panel (label, type, local/remote host+port, SSH host, auto-start)');
  await step(c.notes, 'validation', () async {
    await typeKey(t, 'pf-label', 'SSH over tunnel');
    await typeKey(t, 'pf-local-port', '70000');
    await typeKey(t, 'pf-remote-host', '127.0.0.1');
    await typeKey(t, 'pf-remote-port', '22');
    await tapText(t, 'Add Rule', wait: 600);
    await c.snap('$s/03-validation-port', 'Local port 70000 rejected: "Local port must be between 1 and 65535."');
  });
  await typeKey(t, 'pf-local-port', '2200');
  await step(c.notes, 'host', () async {
    await tapKey(t, 'pf-host', wait: 600);
    await tapText(t, 'Demo Server', index: 0, wait: 500);
  });
  await c.snap('$s/04-local-rule-filled', 'Local rule filled: localhost:2200 -> 127.0.0.1:22 via Demo Server');
  await tapText(t, 'Add Rule', wait: 800);
  await c.snap('$s/05-rule-list', 'Rule list with the new local rule');
  await step(c.notes, 'dynamic', () async {
    await tapText(t, 'NEW RULE', wait: 700);
    await typeKey(t, 'pf-label', 'SOCKS proxy');
    await tapKey(t, 'pf-type', wait: 600);
    await c.snap('$s/06-type-menu', 'Rule type dropdown: Local / Remote / Dynamic SOCKS5');
    await tapText(t, 'Dynamic SOCKS5', wait: 500);
    await typeKey(t, 'pf-local-port', '1080');
    await tapKey(t, 'pf-host', wait: 600);
    await tapText(t, 'Demo Server', index: 0, wait: 500);
    await c.snap('$s/07-dynamic-rule-filled', 'Dynamic SOCKS5 rule (no remote host/port)');
    await tapText(t, 'Add Rule', wait: 800);
  });
  await step(c.notes, 'start', () async {
    await tapTooltip(t, 'Start', wait: 1500);
    await sleepPump(t, 1500);
    await c.snap('$s/08-running', 'First rule started: Running state');
    _probe = await Socket.connect('127.0.0.1', 2200);
    await sleepPump(t, 1500);
    await c.snap('$s/09-running-connections', 'Running tunnel with an active connection counted');
  });
  await step(c.notes, 'edit', () async {
    await tapText(t, 'SSH over tunnel', wait: 700);
    await c.snap('$s/10-rule-editor', 'Clicking a rule opens the editor');
    await pressEscape(t);
  });
  await step(c.notes, 'delete', () async {
    await tapTooltip(t, 'Delete', wait: 700);
    await c.snap('$s/11-delete-confirm', 'Delete rule confirmation');
    if (find.text('Cancel').evaluate().isNotEmpty) await tapText(t, 'Cancel', wait: 500);
  });
  await _probe?.close();
  _probe = null;
}
