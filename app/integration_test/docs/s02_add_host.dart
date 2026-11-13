// 02 add host (SSH, password): panel sections, validation, filled form, save.
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '02-add-host';

Future<void> runAddHost(JourneyContext c) async {
  final t = c.t;
  await tapText(t, 'New host', index: 0, wait: 800);
  await c.snap('$s/01-new-host-panel', 'New host panel (SSH): general + credentials, empty');
  Future<void> section(String n, String label, String cap) => step(c.notes, label, () async {
        await scrollTo(t, find.text(label));
        await c.snap('$s/$n', cap);
      });
  await section('02-section-auth', 'AUTH METHOD', 'Panel scrolled to AUTH METHOD');
  await section('03-section-chain', 'CONNECTION CHAIN', 'Panel scrolled to CONNECTION CHAIN (jump hosts), empty');
  await section('04-section-template', 'SESSION TEMPLATE', 'Panel scrolled to SESSION TEMPLATE (working dir, env vars, startup snippet, per-host terminal overrides)');
  await section('05-section-options', 'OPTIONS', 'Panel scrolled to OPTIONS (auto-record, redaction, shell integration, agent forwarding)');
  await section('06-section-group', 'GROUP & TAGS', 'Panel scrolled to GROUP & TAGS');
  await step(c.notes, 'validation', () async {
    await tapKey(t, 'host-save-button', wait: 500);
    await scrollTo(t, byKeyStr('host-label-field'), alignment: 0.0);
    await c.snap('$s/07-validation-required', 'Save with empty hostname: "Required" validation error');
    await typeKey(t, 'host-address-field', '127.0.0.1');
    await typeKey(t, 'host-port-field', '70000');
    await tapKey(t, 'host-save-button', wait: 500);
    await c.snap('$s/08-validation-port', 'Port 70000 rejected by validation');
  });
  await typeKey(t, 'host-label-field', 'Demo Server');
  await typeKey(t, 'host-address-field', '127.0.0.1');
  await typeKey(t, 'host-port-field', '2222');
  await typeKey(t, 'host-username-field', 'demo');
  await step(c.notes, 'password', () => typeKey(t, 'host-password-field', 'demo1234'));
  await step(c.notes, 'group', () => typeKey(t, 'host-group-field', 'Demo'));
  await step(c.notes, 'tags', () => typeKey(t, 'host-tags-field', 'docs, linux'));
  await scrollTo(t, byKeyStr('host-label-field'), alignment: 0.0);
  await c.snap('$s/09-filled-form', 'Host form filled: Demo Server, 127.0.0.1:2222, demo / password');
  await step(c.notes, 'test', () async {
    await tapKey(t, 'host-test-button', wait: 300);
    await waitFor(t, () => byKeyStr('host-test-result').evaluate().isNotEmpty, seconds: 20, throwOnTimeout: false);
    await c.snap('$s/10-test-result', 'Test button result');
  });
  await tapKey(t, 'host-save-button', wait: 900);
  await sleepPump(t, 600);
  await c.snap('$s/11-dashboard-with-host', 'Dashboard after saving: the new host card');
}
