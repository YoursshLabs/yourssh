// 05 more hosts: key-auth, bastion, internal host behind the bastion (chain).
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';
import 's03_connect.dart' show typeCmd;
import 'package:yourssh/models/ssh_session.dart';

const s = '05-more-hosts';

Future<void> runMoreHosts(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Hosts');
  // Host 2: key auth
  await tapText(t, 'New host', index: 0, wait: 800);
  await typeKey(t, 'host-label-field', 'Demo Key Auth');
  await typeKey(t, 'host-address-field', '127.0.0.1');
  await typeKey(t, 'host-port-field', '2222');
  await typeKey(t, 'host-username-field', 'demo');
  await step(c.notes, 'auth select', () async {
    await scrollTo(t, find.text('AUTH METHOD'));
    await tapKey(t, 'auth-method-select', wait: 600);
    await c.snap('$s/01-auth-method-menu', 'Auth method dropdown: Password / Private Key / SSH Agent');
    await tapText(t, 'Private Key', wait: 600);
    await tapKey(t, 'auth-key-select', wait: 600);
    await c.snap('$s/02-key-select-menu', 'Choosing a keychain key for key authentication');
    await tapText(t, 'demo_ed25519', exact: false, wait: 600);
    await c.snap('$s/03-key-auth-form', 'Key-auth host form with the imported key selected');
  });
  await tapKey(t, 'host-save-button', wait: 900);
  // Host 3: bastion
  await tapText(t, 'New host', index: 0, wait: 800);
  await typeKey(t, 'host-label-field', 'Bastion');
  await typeKey(t, 'host-address-field', '127.0.0.1');
  await typeKey(t, 'host-port-field', '2223');
  await typeKey(t, 'host-username-field', 'demo');
  await typeKey(t, 'host-password-field', 'demo1234');
  await tapKey(t, 'host-save-button', wait: 900);
  // Host 4: internal through bastion
  await tapText(t, 'New host', index: 0, wait: 800);
  await typeKey(t, 'host-label-field', 'DB Internal');
  await typeKey(t, 'host-address-field', 'db-internal');
  await typeKey(t, 'host-port-field', '22');
  await typeKey(t, 'host-username-field', 'demo');
  await typeKey(t, 'host-password-field', 'demo1234');
  await step(c.notes, 'chain', () async {
    await scrollTo(t, find.text('CONNECTION CHAIN'), alignment: 0.05);
    await c.snap('$s/04-chain-empty', 'Connection chain editor before adding a hop');
    await tapText(t, 'Add a Host', wait: 700);
    await c.snap('$s/05-chain-picker', 'Add-a-Host picker lists saved hosts to use as a jump host');
    await t.tap(find.text('Bastion').last, warnIfMissed: false);
    await sleepPump(t, 700);
    await c.snap('$s/06-chain-with-hop', 'Chain editor: Bastion hop -> destination card');
  });
  await tapKey(t, 'host-save-button', wait: 900);
  await sleepPump(t, 600);
  await c.snap('$s/07-dashboard-four-hosts', 'Dashboard with four hosts');
  // Connect through the chain
  await step(c.notes, 'connect chain', () async {
    await doubleTap(t, find.text('DB Internal').first);
    await waitFor(t, () => c.sessions.sshSessions.any((x) => x.host.label == 'DB Internal' && x.status == SessionStatus.connected),
        seconds: 40, what: 'db connected');
    await sleepPump(t, 2500);
    await typeCmd(c, 'hostname');
    await c.snap('$s/08-chain-terminal', 'Connected through the bastion: `hostname` prints db-internal; status bar shows the jump chain');
  });
}
