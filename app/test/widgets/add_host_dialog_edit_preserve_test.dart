import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/widgets/add_host_dialog.dart';

/// Regression tests for #51 — editing a host through the quick AddHostDialog
/// must not reset fields the dialog has no UI for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  late ({Host host, String password})? popped;

  // Settle, then swallow the pre-existing RenderFlex overflow from the fixed
  // 400px dialog (see add_host_dialog_sftp_test.dart). Re-throws anything else.
  Future<void> settleIgnoringOverflow(WidgetTester tester) async {
    await tester.pumpAndSettle();
    while (true) {
      final ex = tester.takeException();
      if (ex == null) break;
      final msg = ex.toString();
      if (!msg.contains('overflowed') && !msg.contains('RenderFlex')) {
        throw ex;
      }
    }
  }

  Future<void> pumpDialog(WidgetTester tester, {Host? existing}) async {
    popped = null;
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<KeyProvider>(
        create: (_) => KeyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  popped = await showDialog<({Host host, String password})>(
                    context: context,
                    builder: (_) => AddHostDialog(existing: existing),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleIgnoringOverflow(tester);
  }

  testWidgets('editing preserves fields the dialog has no UI for',
      (tester) async {
    final created = DateTime(2025, 1, 2, 3, 4, 5);
    final existing = Host(
      label: 'srv',
      host: '1.2.3.4',
      username: 'root',
      group: 'production',
      tags: ['eu-west', 'k8s'],
      autoRecord: true,
      shellIntegration: false,
      jumpHostIds: ['jump-1'],
      detectedOs: 'ubuntu',
      agentForwarding: true,
      createdAt: created,
    );

    await pumpDialog(tester, existing: existing);

    // Change one exposed field so the edit is a real edit.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Label'), 'srv-renamed');
    await tester.tap(find.text('Save'));
    await settleIgnoringOverflow(tester);

    expect(popped, isNotNull);
    final h = popped!.host;
    expect(h.id, existing.id);
    expect(h.label, 'srv-renamed');
    // Everything the dialog has no UI for must survive (#51):
    expect(h.group, 'production');
    expect(h.tags, ['eu-west', 'k8s']);
    expect(h.autoRecord, isTrue);
    expect(h.shellIntegration, isFalse);
    expect(h.jumpHostId, 'jump-1');
    expect(h.detectedOs, 'ubuntu');
    expect(h.agentForwarding, isTrue);
    expect(h.createdAt, created);
  });

  testWidgets('switching auth from key to password clears keyId',
      (tester) async {
    // Seed KeyProvider so the SSH Key dropdown has an item matching the
    // host's keyId (the dropdown asserts its value is among the items).
    SharedPreferences.setMockInitialValues({
      'yourssh.keys':
          '[{"id":"key-1","label":"test key","algorithm":"ed25519",'
              '"publicKey":"","privateKeyPath":"/tmp/nokey",'
              '"addedAt":"2025-01-01T00:00:00.000"}]',
    });
    final existing = Host(
      label: 'srv',
      host: '1.2.3.4',
      username: 'root',
      authType: AuthType.privateKey,
      keyId: 'key-1',
    );

    await pumpDialog(tester, existing: existing);

    // Auth dropdown currently shows "Private Key"; switch to Password.
    await tester.tap(find.text('Private Key'));
    await settleIgnoringOverflow(tester);
    await tester.tap(find.text('Password').last);
    await settleIgnoringOverflow(tester);

    await tester.tap(find.text('Save'));
    await settleIgnoringOverflow(tester);

    expect(popped, isNotNull);
    expect(popped!.host.authType, AuthType.password);
    expect(popped!.host.keyId, isNull);
  });
}
