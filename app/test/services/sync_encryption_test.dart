import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sync_encryption.dart';

void main() {
  group('SyncEncryption', () {
    const syncId = 'X7KDM2PQ3RVA';

    test('encrypt then decrypt returns original plaintext', () async {
      const plaintext = '{"hosts":[],"passwords":{}}';
      final encrypted = await SyncEncryption.encrypt(plaintext, syncId);
      final decrypted = await SyncEncryption.decrypt(encrypted, syncId);
      expect(decrypted, plaintext);
    });

    test('two encrypts of same plaintext produce different ciphertext (IV uniqueness)', () async {
      const plaintext = '{"hosts":[]}';
      final a = await SyncEncryption.encrypt(plaintext, syncId);
      final b = await SyncEncryption.encrypt(plaintext, syncId);
      expect(a, isNot(b));
    });

    test('wrong key throws ArgumentError', () async {
      const plaintext = '{"hosts":[]}';
      final encrypted = await SyncEncryption.encrypt(plaintext, syncId);
      expect(
        () => SyncEncryption.decrypt(encrypted, 'WRONGWRONGWRONG'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
