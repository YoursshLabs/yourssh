import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class SyncEncryption {
  static const _salt = 'yourssh-sync-v1';
  static const _iterations = 100000;
  static final _algorithm = AesGcm.with256bits();
  static final _keyCache = <String, SecretKey>{};

  static Future<SecretKey> _deriveKey(String syncId) async {
    if (_keyCache.containsKey(syncId)) return _keyCache[syncId]!;
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(syncId)),
      nonce: utf8.encode(_salt),
    );
    _keyCache[syncId] = key;
    return key;
  }

  /// Returns base64(iv[12] + ciphertext + authTag[16])
  static Future<String> encrypt(String plaintext, String syncId) async {
    final key = await _deriveKey(syncId);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    final combined = Uint8List(
      secretBox.nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length,
    );
    combined.setAll(0, secretBox.nonce);
    combined.setAll(secretBox.nonce.length, secretBox.cipherText);
    combined.setAll(
      secretBox.nonce.length + secretBox.cipherText.length,
      secretBox.mac.bytes,
    );
    return base64.encode(combined);
  }

  /// Decrypts base64(iv[12] + ciphertext + authTag[16]); throws ArgumentError on bad key or malformed data.
  static void evictKey(String syncId) {
    _keyCache.remove(syncId);
  }

  static Future<String> decrypt(String encoded, String syncId) async {
    final key = await _deriveKey(syncId);
    final combined = base64.decode(encoded);
    const ivLen = 12;
    const tagLen = 16;
    if (combined.length < ivLen + tagLen) {
      throw ArgumentError('invalid sync code');
    }
    final nonce = combined.sublist(0, ivLen);
    final cipherText = combined.sublist(ivLen, combined.length - tagLen);
    final mac = Mac(combined.sublist(combined.length - tagLen));
    try {
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final clearBytes = await _algorithm.decrypt(secretBox, secretKey: key);
      return utf8.decode(clearBytes);
    } catch (_) {
      throw ArgumentError('invalid sync code');
    }
  }
}
