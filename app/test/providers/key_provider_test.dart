import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  _keyRemovalTests();

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
  final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
      'test_key_${DateTime.now().millisecondsSinceEpoch}');
  f.writeAsStringSync('placeholder');
  return f.path;
}

void _keyRemovalTests() {
  group('KeyProvider removal', () {
    late Directory sshDir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sshDir = Directory.systemTemp.createTempSync('ssh_dir_');
      File('${sshDir.path}/id_ed25519').writeAsStringSync('k');
      File('${sshDir.path}/id_ed25519.pub').writeAsStringSync('pub');
    });
    tearDown(() => sshDir.deleteSync(recursive: true));

    test('deleteKey deletes the stored passphrase', () async {
      final provider = KeyProvider(discoverSshKeys: false);
      await provider.ready;
      final deleted = <String>[];
      provider.deletePassphrase = (id) async => deleted.add(id);
      final entry = await provider.addKeyFromFile(_tmpKeyFile(), 'k');

      await provider.deleteKey(entry.id);

      expect(deleted, [entry.id]);
    });

    test('a failing passphrase delete does not break removal', () async {
      final provider = KeyProvider(discoverSshKeys: false);
      await provider.ready;
      provider.deletePassphrase = (id) async => throw Exception('boom');
      final entry = await provider.addKeyFromFile(_tmpKeyFile(), 'k');

      await provider.deleteKey(entry.id);

      expect(provider.keys, isEmpty);
    });

    test('removed auto-discovered key is not re-added on next launch', () async {
      final first = KeyProvider(sshDirPath: sshDir.path);
      await first.ready;
      expect(first.keys, hasLength(1));
      await first.deleteKey(first.keys.first.id);

      final second = KeyProvider(sshDirPath: sshDir.path);
      await second.ready;

      expect(second.keys, isEmpty);
    });

    test('explicit re-import clears the dismissal', () async {
      final first = KeyProvider(sshDirPath: sshDir.path);
      await first.ready;
      await first.deleteKey(first.keys.first.id);

      final second = KeyProvider(sshDirPath: sshDir.path);
      await second.ready;
      await second.addKeyFromFile('${sshDir.path}/id_ed25519', 'again');
      expect(second.keys, hasLength(1));
      await second.deleteKey(second.keys.first.id);

      // Re-import then (no) removal: dismissal was cleared, so re-importing
      // and relaunching keeps the key.
      final third = KeyProvider(sshDirPath: sshDir.path);
      await third.ready;
      await third.addKeyFromFile('${sshDir.path}/id_ed25519', 'again');
      final fourth = KeyProvider(sshDirPath: sshDir.path);
      await fourth.ready;
      expect(fourth.keys, hasLength(1));
    });
  });
}
