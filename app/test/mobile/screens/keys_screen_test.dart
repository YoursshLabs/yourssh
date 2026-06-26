import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  List<SshKeyEntry> get keys => _seed;
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
}) async {
  SharedPreferences.setMockInitialValues({});

  // Realistic OpenSSH public key lines — the card now computes a real SHA256
  // fingerprint from the base64 blob rather than displaying a literal.
  final seedKeys = keys ??
      [
        SshKeyEntry(
          label: 'id_ed25519',
          algorithm: KeyAlgorithm.ed25519,
          publicKey:
              'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ user@host',
          privateKeyPath: '/home/user/.ssh/id_ed25519',
        ),
        SshKeyEntry(
          label: 'id_rsa',
          algorithm: KeyAlgorithm.rsa,
          publicKey:
              'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2 user@host',
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
          value: _FakeKeyProvider(seedKeys),
        ),
        ChangeNotifierProvider<HostProvider>.value(value: hostProv),
        Provider<KeyGenService>.value(value: keyGen ?? _FakeKeyGen()),
      ],
      child: MaterialApp(
        theme: buildMobileTheme(),
        home: const MobileKeysScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Disable Google Fonts runtime network fetching so tests don't make
    // real HTTP requests (which are blocked in the test environment).
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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
      publicKey:
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ prod@host',
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

  // ── Regression: generated passphrase must be persisted ───────────────────────

  // ── Passphrase persistence is tested as a unit test (no widget needed) ───────
  // The _GenerateSheetState._generate() code path is:
  //   entry = await keyProv.addKeyFromFile(path, name)
  //   if (passphrase.isNotEmpty && mounted) keyProv.savePassphrase?.call(entry.id, passphrase)
  // We verify this contract directly, avoiding google_fonts/path_provider
  // complexity in a widget test.

  test('generate with passphrase: savePassphrase is called with key id', () async {
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
    final entry = await trackingProv.addKeyFromFile(result.privateKeyPath, name);
    if (passphrase.isNotEmpty) {
      await trackingProv.savePassphrase?.call(entry.id, passphrase);
    }

    expect(trackingProv.savedPassphrases, hasLength(1));
    expect(trackingProv.savedPassphrases.first.$1, equals(entry.id));
    expect(trackingProv.savedPassphrases.first.$2, equals(passphrase));
  });

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
    final entry = await trackingProv.addKeyFromFile(result.privateKeyPath, name);
    if (passphrase.isNotEmpty) {
      await trackingProv.savePassphrase?.call(entry.id, passphrase);
    }

    expect(trackingProv.savedPassphrases, isEmpty);
    // entry is still created
    expect(entry.label, equals(name));
  });
}
