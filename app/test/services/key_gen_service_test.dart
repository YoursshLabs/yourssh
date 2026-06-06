import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/key_gen_service.dart';

void main() {
  late Directory tmp;
  final svc = KeyGenService();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('keygen_test');
  });

  tearDown(() => tmp.delete(recursive: true));

  group('sanitizeKeyName', () {
    test('keeps safe chars, replaces the rest', () {
      expect(KeyGenService.sanitizeKeyName('id_ed25519'), 'id_ed25519');
      expect(KeyGenService.sanitizeKeyName('my key/2!'), 'my_key_2_');
    });
  });

  group('buildDeployCommand', () {
    test('quotes the key and is idempotent via grep -qxF', () {
      final cmd = KeyGenService.buildDeployCommand('ssh-ed25519 AAAA test');
      expect(cmd, contains("grep -qxF 'ssh-ed25519 AAAA test'"));
      expect(cmd, contains('echo EXISTS'));
      expect(cmd, contains('echo ADDED'));
      expect(cmd, contains('chmod 700'));
      expect(cmd, contains('chmod 600'));
    });

    test('single quotes in the line are escaped', () {
      final cmd = KeyGenService.buildDeployCommand("key with ' quote");
      expect(cmd, contains(r"'key with '\'' quote'"));
    });
  });

  group('generateEd25519', () {
    test('writes a parseable key + .pub line, registers paths', () async {
      final r = await svc.generateEd25519(
          name: 'test key', passphrase: '', dir: tmp.path);
      expect(r.privateKeyPath, '${tmp.path}/test_key');
      final pem = File(r.privateKeyPath).readAsStringSync();
      expect(SSHKeyPair.fromPem(pem).single.name, 'ssh-ed25519');
      final pubLine = File('${r.privateKeyPath}.pub').readAsStringSync();
      expect(pubLine, startsWith('ssh-ed25519 '));
      expect(pubLine.trim(), endsWith(' test key'));
      expect(r.publicKeyLine, pubLine.trim());
      if (!Platform.isWindows) {
        final mode = File(r.privateKeyPath).statSync().mode & 0xFFF;
        expect(mode, 0x180, reason: 'private key must be 0600');
      }
    });

    test('passphrase produces an encrypted PEM that decrypts', () async {
      final r = await svc.generateEd25519(
          name: 'enc', passphrase: 's3cret', dir: tmp.path);
      final pem = File(r.privateKeyPath).readAsStringSync();
      expect(SSHKeyPair.isEncryptedPem(pem), isTrue);
      expect(SSHKeyPair.fromPem(pem, 's3cret'), hasLength(1));
    });
  });

  group('sshKeygenArgs', () {
    test('rsa gets -b 4096, ecdsa gets -b 256, ed25519 gets no -b', () {
      expect(
          KeyGenService.sshKeygenArgs(
              type: 'rsa', keyPath: '/k', comment: 'c', passphrase: ''),
          containsAllInOrder(['-t', 'rsa', '-b', '4096']));
      expect(
          KeyGenService.sshKeygenArgs(
              type: 'ecdsa', keyPath: '/k', comment: 'c', passphrase: ''),
          containsAllInOrder(['-t', 'ecdsa', '-b', '256']));
      expect(
          KeyGenService.sshKeygenArgs(
              type: 'ed25519', keyPath: '/k', comment: 'c', passphrase: ''),
          isNot(contains('-b')));
    });
  });
}
