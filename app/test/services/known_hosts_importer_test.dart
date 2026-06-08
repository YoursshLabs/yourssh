import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/util/known_hosts_importer.dart';

// A base64-encoded minimal key blob that is valid for parsing.
// ssh-ed25519 key blob: uint32 len + "ssh-ed25519" + uint32 len + 32 bytes of zeros
Uint8List _buildEd25519KeyBlob() {
  final keyType = utf8.encode('ssh-ed25519');
  final keyBytes = Uint8List(32); // 32 zero bytes
  final buf = BytesBuilder();
  // key type length (4 bytes big-endian) + key type
  buf.add([0, 0, 0, keyType.length]);
  buf.add(keyType);
  // key bytes length (4 bytes big-endian) + key bytes
  buf.add([0, 0, 0, keyBytes.length]);
  buf.add(keyBytes);
  return buf.toBytes();
}

String _b64Key() => base64.encode(_buildEd25519KeyBlob());

String _fingerprint(String b64) {
  final bytes = base64.decode(b64);
  return KnownHost.bytesToFingerprint(
    Uint8List.fromList(md5.convert(bytes).bytes),
  );
}

void main() {
  group('KnownHostsImporter', () {
    final b64 = _b64Key();

    test('happy path: plain host line → port 22', () {
      final result = KnownHostsImporter.parse('example.com ssh-ed25519 $b64\n');
      expect(result.length, 1);
      expect(result.first.host, 'example.com');
      expect(result.first.port, 22);
      expect(result.first.keyType, 'ssh-ed25519');
      expect(result.first.fingerprint, _fingerprint(b64));
    });

    test('bracket format: [192.168.1.1]:2222 → port 2222', () {
      final result =
          KnownHostsImporter.parse('[192.168.1.1]:2222 ecdsa-sha2-nistp256 $b64\n');
      expect(result.length, 1);
      expect(result.first.host, '192.168.1.1');
      expect(result.first.port, 2222);
    });

    test('comma-separated hosts: host1,host2 → two entries', () {
      final result =
          KnownHostsImporter.parse('host1,host2 ssh-ed25519 $b64\n');
      expect(result.length, 2);
      final hosts = result.map((h) => h.host).toSet();
      expect(hosts, containsAll(['host1', 'host2']));
    });

    test('@cert-authority line is skipped', () {
      final result = KnownHostsImporter.parse(
          '@cert-authority example.com ssh-ed25519 $b64\n');
      expect(result, isEmpty);
    });

    test('hashed line (|1|...) is skipped', () {
      final result = KnownHostsImporter.parse(
          '|1|abc123|xyz456== ssh-ed25519 $b64\n');
      expect(result, isEmpty);
    });

    test('!negation: ! stripped, host imported as "negation"', () {
      final result =
          KnownHostsImporter.parse('!negation ssh-ed25519 $b64\n');
      expect(result.length, 1);
      expect(result.first.host, 'negation');
    });

    test('malformed base64 → skipped without crash', () {
      final result =
          KnownHostsImporter.parse('example.com ssh-ed25519 !!not-valid-base64!!\n');
      expect(result, isEmpty);
    });

    test('empty input → empty result', () {
      expect(KnownHostsImporter.parse(''), isEmpty);
    });

    test('blank lines and comments are skipped', () {
      final content = '''
# This is a comment

example.com ssh-ed25519 $b64
''';
      final result = KnownHostsImporter.parse(content);
      expect(result.length, 1);
      expect(result.first.host, 'example.com');
    });

    test('line with fewer than 3 fields is skipped', () {
      final result = KnownHostsImporter.parse('example.com ssh-ed25519\n');
      expect(result, isEmpty);
    });
  });
}
