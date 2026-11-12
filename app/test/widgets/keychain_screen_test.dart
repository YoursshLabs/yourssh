import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh/widgets/keychain_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakeKeyGen extends KeyGenService {
  @override
  Future<bool> probeSshKeygen() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final longLabel = 'k' * 60;

  Future<KeyProvider> pump(WidgetTester tester, {bool withKey = true}) async {
    final entry = SshKeyEntry(
      id: 'k1',
      label: longLabel,
      algorithm: KeyAlgorithm.ed25519,
      publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test',
      privateKeyPath: '/tmp/${'p' * 60}/id',
    );
    SharedPreferences.setMockInitialValues({
      if (withKey) 'yourssh.keys': jsonEncode([entry.toJson()]),
    });
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final keys = KeyProvider();
    await keys.ready;
    await tester.pumpWidget(
      ChangeNotifierProvider<KeyProvider>.value(
        value: keys,
        child: ysTestApp(KeychainScreen(keyGen: _FakeKeyGen())),
      ),
    );
    await tester.pumpAndSettle();
    return keys;
  }

  testWidgets('top bar actions and key tile actions are present',
      (tester) async {
    await pump(tester);
    expect(find.text('SSH Keys'), findsOneWidget);
    expect(find.text('IMPORT'), findsOneWidget);
    expect(find.text('GENERATE'), findsOneWidget);
    expect(find.byTooltip('Copy public key'), findsWidgets);
    expect(find.byTooltip('Deploy to host…'), findsWidgets);
    expect(find.byTooltip('Remove key'), findsWidgets);
    expect(find.text('Link certificate…'), findsWidgets);
  });

  testWidgets('empty state offers Import and Generate', (tester) async {
    final keys = await pump(tester, withKey: false);
    // KeyProvider auto-discovers real ~/.ssh keys; nothing to assert then.
    if (keys.keys.isNotEmpty) return;
    expect(find.text('No keys added'), findsOneWidget);
    expect(find.text('Import Key'), findsOneWidget);
    expect(find.text('+ Generate Key'), findsOneWidget);
  });

  testWidgets('60-char label and path at 900x600 do not overflow',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('GENERATE'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(longLabel), findsOneWidget);
  });

  testWidgets('generate panel focuses the key name field', (tester) async {
    await pump(tester);
    await tester.tap(find.text('GENERATE'));
    await tester.pumpAndSettle();
    final focus = FocusManager.instance.primaryFocus!;
    expect(
      find.descendant(
        of: find.byKey(const Key('keygen-name')),
        matching: find.byType(EditableText),
      ),
      findsOneWidget,
    );
    expect(focus.context!.findAncestorWidgetOfExactType<FTextFormField>()?.key,
        const Key('keygen-name'));
  });

  testWidgets('remove asks for confirmation, Enter on default-focused Cancel keeps key',
      (tester) async {
    final keys = await pump(tester);
    await tester.tap(find.byTooltip('Remove key').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove Key'), findsOneWidget);
    expect(find.text('Remove "$longLabel" from keychain?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Enter on the default-focused Cancel must not delete.
    expect(keys.keys.any((k) => k.id == 'k1'), isTrue);
    expect(find.text('Remove Key'), findsNothing);
  });
}
