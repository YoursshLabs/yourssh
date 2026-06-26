import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

// ── Fake KeyGenService — ssh-keygen present ───────────────────────────────────

class _FakeKeyGen extends KeyGenService {
  @override
  Future<bool> probeSshKeygen() async => true;
}

// ── Pump helper ───────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  List<SshKeyEntry>? keys,
  List<Host>? hosts,
  KeyGenService? keyGen,
}) async {
  SharedPreferences.setMockInitialValues({});

  final seedKeys = keys ??
      [
        SshKeyEntry(
          label: 'id_ed25519',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: 'SHA256:abcdefABCDEF1234567890==',
          privateKeyPath: '/home/user/.ssh/id_ed25519',
        ),
        SshKeyEntry(
          label: 'id_rsa',
          algorithm: KeyAlgorithm.rsa,
          publicKey: 'SHA256:rstuvwRSTUVW0987654321==',
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
      publicKey: 'SHA256:prod==',
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
    // subtitle "1 keys · 1 in use"
    expect(find.textContaining('1 in use'), findsOneWidget);
  });
}
