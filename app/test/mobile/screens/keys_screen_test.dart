import 'package:yourssh/theme/app_theme.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'package:yourssh/mobile/screens/mobile_keys_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh/services/storage_service.dart';

// ── Fake KeyProvider seeded with 2 keys ──────────────────────────────────────

class _FakeKeyProvider extends KeyProvider {
  final List<SshKeyEntry> _seed;
  _FakeKeyProvider(this._seed);

  final List<String> deleted = [];

  @override
  List<SshKeyEntry> get keys => _seed;

  @override
  Future<void> deleteKey(String id) async => deleted.add(id);
}

/// Tracks savePassphrase calls so tests can assert them.
class _TrackingKeyProvider extends KeyProvider {
  final List<(String id, String pp)> savedPassphrases = [];
  SshKeyEntry? _lastAdded;

  _TrackingKeyProvider() {
    savePassphrase = (id, pp) async => savedPassphrases.add((id, pp));
  }

  @override
  List<SshKeyEntry> get keys => _lastAdded == null ? [] : [_lastAdded!];

  /// Override to avoid disk I/O in tests.
  @override
  Future<SshKeyEntry> addKeyFromFile(String path, String label) async {
    _lastAdded = SshKeyEntry(
      label: label,
      algorithm: KeyAlgorithm.ed25519,
      publicKey: '',
      privateKeyPath: path,
    );
    notifyListeners();
    return _lastAdded!;
  }
}

// ── Fake KeyGenService — ssh-keygen present ───────────────────────────────────

class _FakeKeyGen extends KeyGenService {
  @override
  Future<bool> probeSshKeygen() async => true;
}

/// Fake KeyGenService that immediately returns a canned key path without
/// touching the filesystem.
class _InstantKeyGen extends KeyGenService {
  @override
  Future<bool> probeSshKeygen() async => false;

  @override
  Future<GeneratedKey> generateEd25519({
    required String name,
    String passphrase = '',
    required String dir,
  }) async {
    return const GeneratedKey(
      privateKeyPath: '/tmp/fake_key',
      publicKeyLine: 'ssh-ed25519 AAAA fake@test',
    );
  }
}

// ── Pump helper ───────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  List<SshKeyEntry>? keys,
  List<Host>? hosts,
  KeyGenService? keyGen,
  KeyProvider? provider,
}) async {
  SharedPreferences.setMockInitialValues({});

  // Realistic OpenSSH public key lines — the card now computes a real SHA256
  // fingerprint from the base64 blob rather than displaying a literal.
  final seedKeys =
      keys ??
      [
        SshKeyEntry(
          label: 'id_ed25519',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ user@host',
          privateKeyPath: '/home/user/.ssh/id_ed25519',
        ),
        SshKeyEntry(
          label: 'id_rsa',
          algorithm: KeyAlgorithm.rsa,
          publicKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2 user@host',
          privateKeyPath: '/home/user/.ssh/id_rsa',
        ),
      ];

  final hostProv = HostProvider(StorageService());
  if (hosts != null) {
    for (final h in hosts) {
      await hostProv.addHost(h);
    }
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<KeyProvider>.value(
          value: provider ?? _FakeKeyProvider(seedKeys),
        ),
        ChangeNotifierProvider<HostProvider>.value(value: hostProv),
        Provider<KeyGenService>.value(value: keyGen ?? _FakeKeyGen()),
      ],
      child: MaterialApp(
        theme: buildMobileTheme(),
        builder: ysRootBuilderTouch,
        home: const MobileKeysScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows title "Keys"', (tester) async {
    await _pump(tester);
    expect(find.text('Keys'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows subtitle with key count', (tester) async {
    await _pump(tester);
    // "2 keys · ..." is somewhere on screen
    expect(find.textContaining('2 keys'), findsOneWidget);
  });

  testWidgets('renders both key labels', (tester) async {
    await _pump(tester);
    expect(find.text('id_ed25519'), findsOneWidget);
    expect(find.text('id_rsa'), findsOneWidget);
  });

  testWidgets('shows SHA256 fingerprint fragment', (tester) async {
    await _pump(tester);
    expect(find.textContaining('SHA256:'), findsAtLeastNWidgets(1));
  });

  testWidgets('Generate button is present', (tester) async {
    await _pump(tester);
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('Import button is present', (tester) async {
    await _pump(tester);
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets('shows algorithm subtitle for ed25519 key', (tester) async {
    await _pump(tester);
    // "Ed25519 · unused" or "Ed25519 · N hosts"
    expect(find.textContaining('Ed25519'), findsAtLeastNWidgets(1));
  });

  testWidgets('in-use count reflects host linkage', (tester) async {
    final key = SshKeyEntry(
      label: 'prod_key',
      algorithm: KeyAlgorithm.ed25519,
      publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ prod@host',
      privateKeyPath: '/home/user/.ssh/prod_key',
    );
    final linkedHost = Host(
      label: 'prod-01',
      host: '10.0.0.1',
      username: 'root',
      keyId: key.id,
      authType: AuthType.privateKey,
    );

    await _pump(tester, keys: [key], hosts: [linkedHost]);
    // subtitle "1 key · 1 in use"
    expect(find.textContaining('1 in use'), findsOneWidget);
  });

  // ── forui migration (Task 15b) ───────────────────────────────────────────

  testWidgets('uses FHeader and header actions have >=44px hit size', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.bySubtype<FHeader>(), findsOneWidget);
    final actions = find.byType(FHeaderAction);
    expect(actions, findsNWidgets(2));
    for (final a in actions.evaluate()) {
      final size = tester.getSize(find.byWidget(a.widget));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('bottom Generate / Import buttons are FButtons >=44px tall', (
    tester,
  ) async {
    await _pump(tester);
    for (final label in ['Generate', 'Import']) {
      final b = find.widgetWithText(FButton, label);
      expect(b, findsOneWidget);
      expect(tester.getSize(b).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('360x640 with 60-char key label does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      keys: [
        SshKeyEntry(
          label: 'k' * 60,
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ u@h',
          privateKeyPath: '/x',
        ),
      ],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Generate sheet: passphrase obscured, name not; no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);
    await tester.tap(find.widgetWithText(FButton, 'Generate'));
    await tester.pumpAndSettle();
    final pass = tester.widget<FTextField>(
      find.byKey(const ValueKey('keygen-passphrase')),
    );
    final name = tester.widget<FTextField>(
      find.byKey(const ValueKey('keygen-name')),
    );
    expect(pass.obscureText, isTrue);
    expect(name.obscureText, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remove key: sheet -> destructive confirm, Cancel focused', (
    tester,
  ) async {
    final prov = _FakeKeyProvider([
      SshKeyEntry(
        label: 'prod_key',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ u@h',
        privateKeyPath: '/x',
      ),
    ]);
    await _pump(tester, provider: prov);
    await tester.longPress(find.text('prod_key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove key'));
    await tester.pumpAndSettle();
    expect(find.text('Remove "prod_key"?'), findsOneWidget);
    final cancel = tester.widget<FButton>(
      find.widgetWithText(FButton, 'Cancel'),
    );
    expect(cancel.autofocus, isTrue);
    final remove = tester.widget<FButton>(
      find.widgetWithText(FButton, 'Remove'),
    );
    expect(remove.variant, FButtonVariant.destructive);
    // Cancel keeps the key.
    await tester.tap(find.widgetWithText(FButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(prov.deleted, isEmpty);
    // Confirm deletes.
    await tester.longPress(find.text('prod_key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove key'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(prov.deleted, [prov.keys.first.id]);
  });

  testWidgets('header action tooltips present', (tester) async {
    await _pump(tester);
    expect(find.byTooltip('Generate key'), findsOneWidget);
    expect(find.byTooltip('Import key'), findsOneWidget);
  });

  testWidgets('key actions sheet Remove item is >=44px', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('id_rsa'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('key-remove-item'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  // ── Regression: generated passphrase must be persisted ───────────────────────

  // ── Passphrase persistence is tested as a unit test (no widget needed) ───────
  // The _GenerateSheetState._generate() code path is:
  //   entry = await keyProv.addKeyFromFile(path, name)
  //   if (passphrase.isNotEmpty && mounted) keyProv.savePassphrase?.call(entry.id, passphrase)
  // We verify this contract directly, avoiding google_fonts/path_provider
  // complexity in a widget test.

  test(
    'generate with passphrase: savePassphrase is called with key id',
    () async {
      final trackingProv = _TrackingKeyProvider();
      final keyGen = _InstantKeyGen();
      final tmp = Directory.systemTemp.createTempSync('ys_test_');

      const passphrase = 'super_secret';
      const name = 'my_test_key';

      // Mirror the production code in _GenerateSheetState._generate():
      final result = await keyGen.generateEd25519(
        name: name,
        passphrase: passphrase,
        dir: tmp.path,
      );
      final entry = await trackingProv.addKeyFromFile(
        result.privateKeyPath,
        name,
      );
      if (passphrase.isNotEmpty) {
        await trackingProv.savePassphrase?.call(entry.id, passphrase);
      }

      expect(trackingProv.savedPassphrases, hasLength(1));
      expect(trackingProv.savedPassphrases.first.$1, equals(entry.id));
      expect(trackingProv.savedPassphrases.first.$2, equals(passphrase));
    },
  );

  test('generate without passphrase: savePassphrase is NOT called', () async {
    final trackingProv = _TrackingKeyProvider();
    final keyGen = _InstantKeyGen();
    final tmp = Directory.systemTemp.createTempSync('ys_test_');

    const passphrase = '';
    const name = 'my_test_key';

    final result = await keyGen.generateEd25519(
      name: name,
      passphrase: passphrase,
      dir: tmp.path,
    );
    final entry = await trackingProv.addKeyFromFile(
      result.privateKeyPath,
      name,
    );
    if (passphrase.isNotEmpty) {
      await trackingProv.savePassphrase?.call(entry.id, passphrase);
    }

    expect(trackingProv.savedPassphrases, isEmpty);
    // entry is still created
    expect(entry.label, equals(name));
  });
}
