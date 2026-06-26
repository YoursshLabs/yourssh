import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Returns the OpenSSH SHA256 fingerprint for a public key line, e.g.:
///   `SHA256:AbCdEf...`
///
/// [openSshPublicKey] should be in the form `<type> <base64blob> [comment]`.
/// Returns `null` if the input cannot be parsed as a valid OpenSSH public key.
String? sha256Fingerprint(String openSshPublicKey) {
  final trimmed = openSshPublicKey.trim();
  if (trimmed.isEmpty) return null;

  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length < 2) return null;

  final blob = parts[1];
  final Uint8List bytes;
  try {
    bytes = base64.decode(_normalizeBase64(blob));
  } catch (_) {
    return null;
  }

  if (bytes.isEmpty) return null;

  final digest = sha256.convert(bytes);
  // OpenSSH omits '=' padding in SHA256: display
  final b64 = base64.encode(digest.bytes).replaceAll('=', '');
  return 'SHA256:$b64';
}

/// Adds padding so [base64.decode] accepts blobs that may lack `=` padding.
String _normalizeBase64(String s) {
  final rem = s.length % 4;
  if (rem == 0) return s;
  return s + '=' * (4 - rem);
}
