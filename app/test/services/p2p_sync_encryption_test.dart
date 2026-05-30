import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/p2p_sync_encryption.dart';

void main() {
  group('P2PSyncEncryption', () {
    test('generateKey returns 32 bytes', () {
      final key = P2PSyncEncryption.generateKey();
      expect(key.length, 32);
    });

    test('generateKey returns different values each call', () {
      final k1 = P2PSyncEncryption.generateKey();
      final k2 = P2PSyncEncryption.generateKey();
      expect(k1, isNot(equals(k2)));
    });

    test('encrypt then decrypt roundtrips plaintext', () async {
      final key = P2PSyncEncryption.generateKey();
      const plaintext = '{"hosts":[],"passwords":{}}';
      final encrypted = await P2PSyncEncryption.encrypt(plaintext, key);
      final decrypted = await P2PSyncEncryption.decrypt(encrypted, key);
      expect(decrypted, plaintext);
    });

    test('decrypt with wrong key throws ArgumentError', () async {
      final key = P2PSyncEncryption.generateKey();
      const plaintext = 'hello';
      final encrypted = await P2PSyncEncryption.encrypt(plaintext, key);
      final wrongKey = P2PSyncEncryption.generateKey();
      expect(
        () async => P2PSyncEncryption.decrypt(encrypted, wrongKey),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decrypt with malformed data throws', () async {
      final key = P2PSyncEncryption.generateKey();
      expect(
        () async => P2PSyncEncryption.decrypt('tooshort', key),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
