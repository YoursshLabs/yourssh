import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../models/known_host.dart';

class KnownHostsImporter {
  /// Parses OpenSSH `known_hosts` file content into [KnownHost] entries.
  ///
  /// Skips: blank lines, comments (#), hashed hostnames (|1|...), and
  /// @cert-authority / @revoked markers.
  static List<KnownHost> parse(String content) {
    final results = <KnownHost>[];
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('@')) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) continue;

      final hostPart = parts[0];
      final keyType = parts[1];
      final base64Key = parts[2];

      // Skip hashed hostnames — can't recover the hostname
      if (hostPart.startsWith('|')) continue;

      Uint8List keyBytes;
      try {
        keyBytes = base64.decode(base64Key);
      } catch (_) {
        continue;
      }

      // dartssh2 passes MD5(key_blob) bytes to verifyHostKey — match that format.
      final fingerprint = KnownHost.bytesToFingerprint(
        Uint8List.fromList(md5.convert(keyBytes).bytes),
      );
      final now = DateTime.now();

      for (final token in hostPart.split(',')) {
        final (host, port) = _parseHostToken(token);
        if (host == null) continue;
        results.add(KnownHost(
          host: host,
          port: port,
          keyType: keyType,
          fingerprint: fingerprint,
          addedAt: now,
        ));
      }
    }
    return results;
  }

  /// Parses `hostname` or `[hostname]:port` into (host, port).
  static (String?, int) _parseHostToken(String token) {
    if (token.startsWith('[')) {
      // [host]:port format
      final closeBracket = token.indexOf(']');
      if (closeBracket == -1) return (null, 22);
      final host = token.substring(1, closeBracket);
      final portStr = token.substring(closeBracket + 2); // skip ]:
      final port = int.tryParse(portStr) ?? 22;
      return (host.isEmpty ? null : host, port);
    }
    // Plain hostname — strip negation marker (!) if present
    final host = token.startsWith('!') ? token.substring(1) : token;
    return (host.isEmpty ? null : host, 22);
  }
}
