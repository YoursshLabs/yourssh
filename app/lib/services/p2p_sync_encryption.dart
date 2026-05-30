import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class P2PSyncEncryption {
  static final _algorithm = AesGcm.with256bits();

  static List<int> generateKey() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(256));
  }

  static Future<String> encrypt(String plaintext, List<int> key) async {
    final secretKey = SecretKey(key);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
    );
    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    combined.setAll(0, secretBox.nonce);
    combined.setAll(secretBox.nonce.length, secretBox.cipherText);
    combined.setAll(
      secretBox.nonce.length + secretBox.cipherText.length,
      secretBox.mac.bytes,
    );
    return base64.encode(combined);
  }

  static Future<String> decrypt(String encoded, List<int> key) async {
    final secretKey = SecretKey(key);
    final List<int> combined;
    try {
      combined = base64.decode(encoded);
    } catch (_) {
      throw ArgumentError('invalid data');
    }
    const ivLen = 12;
    const tagLen = 16;
    if (combined.length < ivLen + tagLen) throw ArgumentError('invalid data');
    final nonce = combined.sublist(0, ivLen);
    final cipherText = combined.sublist(ivLen, combined.length - tagLen);
    final mac = Mac(combined.sublist(combined.length - tagLen));
    try {
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final clearBytes =
          await _algorithm.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clearBytes);
    } catch (_) {
      throw ArgumentError('invalid data');
    }
  }
}
