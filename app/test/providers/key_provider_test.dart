import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  ownedKeysTests();

  group('KeyProvider certificate methods', () {
    test('setCertificate persists certificatePath on the key entry', () async {
      final provider = KeyProvider();
      await Future.delayed(Duration.zero);

      await provider.addKeyFromFile(_tmpKeyFile(), 'test-key');
      await Future.delayed(Duration.zero);

      final key = provider.keys.first;
      await provider.setCertificate(key.id, '/tmp/id_ed25519-cert.pub');

      expect(provider.keys.first.certificatePath, '/tmp/id_ed25519-cert.pub');
    });

    test('removeCertificate clears certificatePath', () async {
      final provider = KeyProvider();
      await Future.delayed(Duration.zero);

      await provider.addKeyFromFile(_tmpKeyFile(), 'test-key');
      await Future.delayed(Duration.zero);

      final key = provider.keys.first;
      await provider.setCertificate(key.id, '/tmp/id_ed25519-cert.pub');
      await provider.removeCertificate(key.id);

      expect(provider.keys.first.certificatePath, isNull);
    });
  });

  test('addKeyFromFile returns the created entry', () async {
    final dir = await Directory.systemTemp.createTemp('kp_test');
    addTearDown(() => dir.delete(recursive: true));
    final keyFile = File('${dir.path}/id_ed25519')..writeAsStringSync('PRIV');
    File('${dir.path}/id_ed25519.pub').writeAsStringSync('ssh-ed25519 AAA c');

    final provider = KeyProvider();
    await Future.delayed(Duration.zero);
    final entry = await provider.addKeyFromFile(keyFile.path, 'my key');
    expect(entry.label, 'my key');
    expect(entry.publicKey, 'ssh-ed25519 AAA c');
    expect(provider.findById(entry.id), isNotNull);
  });
}

String _tmpKeyFile() {
  final f = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'test_key_${DateTime.now().millisecondsSinceEpoch}',
  );
  f.writeAsStringSync('placeholder');
  return f.path;
}

void ownedKeysTests() {
  group('KeyProvider app-owned keys dir', () {
    late Directory root;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync('kp_owned');
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      root.deleteSync(recursive: true);
    });

    Directory keysIn(String name) =>
        Directory('${root.path}/$name/Library/Application Support/keys')
          ..createSync(recursive: true);

    Future<void> seed(String keyPath, {String? cert}) async {
      final seeder = KeyProvider(
        discoverSshKeys: false,
        keysDirPath: () async => '/unused',
      );
      await seeder.ready;
      final e = await seeder.addKeyFromFile(keyPath, 'k');
      if (cert != null) await seeder.setCertificate(e.id, cert);
    }

    test('iOS: stale container path is rebased onto the current keys dir and persisted', () async {
      final a = keysIn('A');
      final b = keysIn('B');
      File('${a.path}/id_ed25519').writeAsStringSync('k');
      File('${a.path}/id_ed25519-cert.pub').writeAsStringSync('c');
      await seed('${a.path}/id_ed25519', cert: '${a.path}/id_ed25519-cert.pub');
      a.parent.parent.parent.deleteSync(recursive: true); // old container gone
      File('${b.path}/id_ed25519').writeAsStringSync('k');
      File('${b.path}/id_ed25519-cert.pub').writeAsStringSync('c');

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final prov = KeyProvider(
        discoverSshKeys: false,
        keysDirPath: () async => b.path,
      );
      await prov.ready;
      expect(prov.keys.single.privateKeyPath, '${b.path}/id_ed25519');
      expect(prov.keys.single.certificatePath, '${b.path}/id_ed25519-cert.pub');

      final again = KeyProvider(
        discoverSshKeys: false,
        keysDirPath: () async => '/unused',
      );
      await again.ready;
      expect(again.keys.single.privateKeyPath, '${b.path}/id_ed25519');
    });

    test('iOS: a path outside the keys dir is left untouched', () async {
      final b = keysIn('B');
      final outside = File('${root.path}/elsewhere/id_rsa')
        ..createSync(recursive: true);
      await seed(outside.path);
      outside.deleteSync();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final prov = KeyProvider(
        discoverSshKeys: false,
        keysDirPath: () async => b.path,
      );
      await prov.ready;
      expect(prov.keys.single.privateKeyPath, outside.path);
    });

    test('non-iOS: stale path is not rebased', () async {
      final a = keysIn('A');
      final b = keysIn('B');
      File('${a.path}/id_ed25519').writeAsStringSync('k');
      await seed('${a.path}/id_ed25519');
      a.parent.parent.parent.deleteSync(recursive: true);
      File('${b.path}/id_ed25519').writeAsStringSync('k');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final prov = KeyProvider(
        discoverSshKeys: false,
        keysDirPath: () async => b.path,
      );
      await prov.ready;
      expect(prov.keys.single.privateKeyPath, '${a.path}/id_ed25519');
    });

    test(
      'deleteKey removes key, .pub and cert files under the keys dir',
      () async {
        final d = keysIn('A');
        final files = [
          File('${d.path}/id_x'),
          File('${d.path}/id_x.pub'),
          File('${d.path}/id_x-cert.pub'),
        ];
        for (final f in files) {
          f.writeAsStringSync('x');
        }
        final prov = KeyProvider(
          discoverSshKeys: false,
          keysDirPath: () async => d.path,
        );
        await prov.ready;
        final e = await prov.addKeyFromFile('${d.path}/id_x', 'x');
        await prov.deleteKey(e.id);
        for (final f in files) {
          expect(f.existsSync(), isFalse, reason: f.path);
        }
      },
    );

    test('deleteKey never touches files outside the keys dir', () async {
      final d = keysIn('A');
      final ssh = Directory('${root.path}/home/.ssh')
        ..createSync(recursive: true);
      final key = File('${ssh.path}/id_rsa')..writeAsStringSync('x');
      final pub = File('${ssh.path}/id_rsa.pub')..writeAsStringSync('x');
      final cert = File('${ssh.path}/id_rsa-cert.pub')..writeAsStringSync('x');
      final prov = KeyProvider(
        discoverSshKeys: false,
        keysDirPath: () async => d.path,
      );
      await prov.ready;
      final e = await prov.addKeyFromFile(key.path, 'r');
      await prov.deleteKey(e.id);
      expect(key.existsSync() && pub.existsSync() && cert.existsSync(), isTrue);
      expect(prov.keys, isEmpty);
    });
  });
}
