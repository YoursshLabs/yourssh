import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh/widgets/keychain_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakeKeyGen extends KeyGenService {
  _FakeKeyGen(this.dir);
  final String dir;
  final generated = <String>[];

  @override
  Future<bool> probeSshKeygen() async => true;

  @override
  Future<GeneratedKey> generateEd25519({
    required String name,
    String passphrase = '',
    required String dir,
  }) async {
    generated.add(name);
    final path = '${this.dir}/$name';
    File(path).writeAsStringSync('private');
    return GeneratedKey(privateKeyPath: path, publicKeyLine: 'ssh-ed25519 AAA');
  }
}

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final longLabel = 'k' * 60;

  late Directory tmp;
  late _FakeKeyGen keyGen;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('keychain_test');
    keyGen = _FakeKeyGen(tmp.path);
    PathProviderPlatform.instance = _FakePaths(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

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
    // discoverSshKeys: false so the test never reads the real ~/.ssh.
    final keys = KeyProvider(discoverSshKeys: false);
    await keys.ready;
    await tester.pumpWidget(
      ChangeNotifierProvider<KeyProvider>.value(
        value: keys,
        child: ysTestApp(KeychainScreen(keyGen: keyGen)),
      ),
    );
    await tester.pumpAndSettle();
    return keys;
  }

  Future<void> hoverTile(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(tester.getCenter(find.text(longLabel)));
    await tester.pump();
  }

  testWidgets('top bar actions and key tile actions are present',
      (tester) async {
    await pump(tester);
    expect(find.text('SSH Keys'), findsOneWidget);
    expect(find.text('IMPORT'), findsOneWidget);
    expect(find.text('GENERATE'), findsOneWidget);
    expect(find.byTooltip('Copy public key'), findsOneWidget);
    expect(find.byTooltip('Deploy to host…'), findsOneWidget);
    expect(find.byTooltip('Remove key'), findsOneWidget);
    expect(find.text('Link certificate…'), findsOneWidget);
  });

  testWidgets('empty state offers Import and Generate', (tester) async {
    await pump(tester, withKey: false);
    expect(find.byType(YsEmptyState), findsOneWidget);
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
    await hoverTile(tester);
    await tester.tap(find.byTooltip('Remove key'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Key'), findsOneWidget);
    expect(find.text('Remove "$longLabel" from keychain?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Enter on the default-focused Cancel must not delete.
    expect(keys.keys.map((k) => k.id), ['k1']);
    expect(find.text('Remove Key'), findsNothing);
  });

  testWidgets('hidden actions ignore taps until revealed', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Remove key'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Remove Key'), findsNothing);
  });

  testWidgets('keyboard focus reveals actions; Enter on Remove confirms',
      (tester) async {
    final keys = await pump(tester);
    var found = false;
    for (var i = 0; i < 12 && !found; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final ctx = FocusManager.instance.primaryFocus?.context;
      found = ctx?.findAncestorWidgetOfExactType<Tooltip>()?.message ==
          'Remove key';
    }
    expect(found, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Remove Key'), findsOneWidget);
    expect(keys.keys, hasLength(1));
  });

  group('generate form', () {
    Future<void> openForm(WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.text('GENERATE'));
      await tester.pumpAndSettle();
    }

    testWidgets('Enter on a valid form generates the key', (tester) async {
      await openForm(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('keygen-name')),
          matching: find.byType(EditableText),
        ),
        'id_ed25519',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      // The submit does real directory IO: alternate real time and pumps.
      for (var i = 0; i < 10 && keyGen.generated.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(keyGen.generated, ['id_ed25519']);
      expect(find.text('Key generated. Public key:'), findsOneWidget);
    });

    testWidgets('Enter on an empty name shows the error, no generation',
        (tester) async {
      await openForm(tester);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('keygen-name')),
          matching: find.byType(EditableText),
        ),
        '',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(keyGen.generated, isEmpty);
    });
  });
}
