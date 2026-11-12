import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for terminal sharing.
///
/// The share code is `ROOM-SECRET` (6 + 16 chars of a 32-symbol alphabet,
/// 80 bits of secret). The broadcast channel name and the AES-256-GCM key are
/// both derived from the full code with domain separation, so the relay never
/// sees the secret and cannot read or forge traffic.
class ShareCrypto {
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const roomLength = 6;
  static const secretLength = 16;
  static const _version = 1;

  final SecretKey _key;
  final String code;

  ShareCrypto._(this.code, this._key);

  /// [code] may be in any user-typed form; it is normalized first.
  factory ShareCrypto(String code) {
    final canonical = normalizeCode(code);
    if (canonical == null) {
      throw const FormatException('Invalid share code');
    }
    final keyBytes = hash.sha256
        .convert(utf8.encode('yourssh-share-key-v1:$canonical'))
        .bytes;
    return ShareCrypto._(canonical, SecretKey(keyBytes));
  }

  static String generateCode() {
    final rng = Random.secure();
    String part(int n) =>
        List.generate(n, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    return '${part(roomLength)}-${part(secretLength)}';
  }

  /// Returns the canonical `ROOM-SECRET` form, or null when malformed.
  static String? normalizeCode(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (s.length != roomLength + secretLength) return null;
    for (final unit in s.codeUnits) {
      if (!alphabet.contains(String.fromCharCode(unit))) return null;
    }
    return '${s.substring(0, roomLength)}-${s.substring(roomLength)}';
  }

  static String channelName(String code) {
    final canonical = normalizeCode(code);
    if (canonical == null) throw const FormatException('Invalid share code');
    final hex = hash.sha256
        .convert(utf8.encode('yourssh-share-chan-v1:$canonical'))
        .toString();
    return 'share:${hex.substring(0, 32)}';
  }

  static final _aes = AesGcm.with256bits();

  Future<Map<String, dynamic>> encrypt(Map<String, dynamic> payload) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: _key,
    );
    return {
      'v': _version,
      'n': base64Encode(box.nonce),
      'c': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Returns the decrypted payload, or null for anything that is not a valid
  /// envelope produced with this code's key.
  Future<Map<String, dynamic>?> decrypt(Map<String, dynamic> envelope) async {
    try {
      if (envelope['v'] != _version) return null;
      final nonce = base64Decode(envelope['n'] as String);
      final all = base64Decode(envelope['c'] as String);
      if (nonce.length != 12 || all.length < 16) return null;
      final cipher = Uint8List.sublistView(all, 0, all.length - 16);
      final mac = Mac(Uint8List.sublistView(all, all.length - 16));
      final clear = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: mac),
        secretKey: _key,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
