import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A 12-character sync code — the single secret for cloud sync. It is the KDF
/// input for payload encryption and never leaves the device; the Supabase row
/// id (`sync_id`) is the one-way [rowId] derived from it. Uses
/// the Crockford Base32 alphabet (excludes the ambiguous I, L, O, U) so codes
/// transcribe cleanly by hand.
class SyncCode {
  SyncCode._();

  /// Crockford Base32: digits 0-9 and A-Z minus I, L, O, U. 32 symbols.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 12;
  static final _rng = Random.secure();

  /// A fresh random 12-char code (~60 bits of entropy).
  static String generate() {
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(alphabet[_rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  /// Upper-cases, strips separators/whitespace, and maps the Crockford-ambiguous
  /// input characters (I, L -> 1; O -> 0) so a hand-typed code still validates.
  static String normalize(String input) {
    return input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll(RegExp('[IL]'), '1')
        .replaceAll('O', '0');
  }

  /// The Supabase row id for [code]: lowercase hex SHA-256 of a domain-separated
  /// normalized code. One-way, so reading `sync_id` from the table does not
  /// reveal the code (the AES-GCM key input).
  static String rowId(String code) => sha256
      .convert(utf8.encode('yourssh-sync-row-v1:${normalize(code)}'))
      .toString();

  /// True when [input] normalizes to exactly 12 chars, all in [alphabet].
  static bool isValid(String input) {
    final n = normalize(input);
    if (n.length != length) return false;
    return n.split('').every(alphabet.contains);
  }

  /// Formats a code as `XXXX-XXXX-XXXX` for display. Returns [code] unchanged if
  /// it does not normalize to 12 chars.
  static String format(String code) {
    final n = normalize(code);
    if (n.length != length) return code;
    return '${n.substring(0, 4)}-${n.substring(4, 8)}-${n.substring(8, 12)}';
  }
}
