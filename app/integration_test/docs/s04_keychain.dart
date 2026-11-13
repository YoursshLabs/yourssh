// 04 keychain: empty, generate, import, key actions, deploy dialog, delete confirm.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'isolation.dart';
import 'nav.dart';
import 'sections.dart';

const s = '04-keychain';

Future<void> runKeychain(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Keychain');
  await c.snap('$s/01-keychain-empty', 'Keychain with no keys: Import Key / Generate Key');
  await step(c.notes, 'generate', () async {
    await tapText(t, 'GENERATE', wait: 700);
    await c.snap('$s/02-generate-panel', 'Generate key panel: name, algorithm (Ed25519 default), passphrase');
    await typeKey(t, 'keygen-name', 'docs-ed25519');
    await c.snap('$s/03-generate-filled', 'Generate panel with a key name entered');
    await tapText(t, 'Generate Key', index: 0, wait: 300);
    await waitText(t, 'Copy public key', seconds: 20, throwOnTimeout: false);
    await c.snap('$s/04-generated-result', 'Key generated: public key shown with Copy public key / Done');
    await tapText(t, 'Done', wait: 600);
  });
  await step(c.notes, 'import', () async {
    DocsFilePicker.next = [Platform.environment['DOCS_KEY_SRC']!];
    await tapText(t, 'IMPORT', wait: 900);
    await sleepPump(t, 600);
    await c.snap('$s/05-key-list', 'Key list after generating and importing a key');
  });
  await step(c.notes, 'hover', () async {
    final tile = find.textContaining('demo_ed25519');
    await hoverOn(t, tile);
    await c.snap('$s/06-key-hover-actions', 'Hovering a key row shows copy public key / deploy / remove actions');
  });
  await step(c.notes, 'deploy', () async {
    await tapTooltip(t, 'Deploy to host…', wait: 700);
    await c.snap('$s/07-deploy-dialog', 'Deploy key to host dialog listing saved hosts');
    await pressEscape(t);
  });
  await step(c.notes, 'delete', () async {
    await hoverOn(t, find.textContaining('docs-ed25519'));
    await tapTooltip(t, 'Remove key', wait: 700);
    await c.snap('$s/08-remove-confirm', 'Remove key confirmation (Cancel focused)');
    await tapText(t, 'Cancel', wait: 500);
  });
}
