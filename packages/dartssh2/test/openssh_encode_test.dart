import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';

void main() {
  group('OpenSSHEd25519KeyPair.generate', () {
    test('produces a working keypair (sign round-trip via PEM)', () {
      final kp = OpenSSHEd25519KeyPair.generate('test@yourssh');
      expect(kp.publicKey.length, 32);
      expect(kp.privateKey.length, 64);
      expect(kp.comment, 'test@yourssh');

      final parsed = SSHKeyPair.fromPem(kp.toPem()).single;
      expect(parsed.name, 'ssh-ed25519');
      final sig = parsed.sign(Uint8List.fromList([1, 2, 3]));
      expect(sig.encode(), isNotEmpty);
    });

    test('two generates differ', () {
      final a = OpenSSHEd25519KeyPair.generate('a');
      final b = OpenSSHEd25519KeyPair.generate('b');
      expect(a.publicKey, isNot(equals(b.publicKey)));
    });
  });

  group('encrypted toPem', () {
    test('round-trips with the right passphrase', () {
      final kp = OpenSSHEd25519KeyPair.generate('enc@yourssh');
      final pem = kp.toPem(passphrase: 'hunter2');
      expect(SSHKeyPair.isEncryptedPem(pem), isTrue);

      final parsed =
          SSHKeyPair.fromPem(pem, 'hunter2').single as OpenSSHEd25519KeyPair;
      expect(parsed.publicKey, kp.publicKey);
      expect(parsed.privateKey, kp.privateKey);
      expect(parsed.comment, 'enc@yourssh');
    });

    test('wrong passphrase throws', () {
      final pem =
          OpenSSHEd25519KeyPair.generate('x').toPem(passphrase: 'right');
      expect(() => SSHKeyPair.fromPem(pem, 'wrong'),
          throwsA(isA<SSHKeyDecryptError>()));
    });

    test('null/empty passphrase stays unencrypted (regression pin)', () {
      final kp = OpenSSHEd25519KeyPair.generate('plain');
      expect(SSHKeyPair.isEncryptedPem(kp.toPem()), isFalse);
      expect(SSHKeyPair.isEncryptedPem(kp.toPem(passphrase: '')), isFalse);
      // Unencrypted output parses without a passphrase.
      expect(SSHKeyPair.fromPem(kp.toPem()), hasLength(1));
    });
  });
}
