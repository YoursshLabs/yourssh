import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';

void main() {
  group('KnownHost', () {
    test('toJson/fromJson round-trips all fields', () {
      final h = KnownHost(
        host: '192.168.1.1',
        port: 22,
        keyType: 'ecdsa-sha2-nistp256',
        fingerprint: 'ab:cd:ef',
        addedAt: DateTime.utc(2026, 5, 29),
      );
      final decoded = KnownHost.fromJson(h.toJson());
      expect(decoded.host, '192.168.1.1');
      expect(decoded.port, 22);
      expect(decoded.keyType, 'ecdsa-sha2-nistp256');
      expect(decoded.fingerprint, 'ab:cd:ef');
      expect(decoded.lookupKey, '192.168.1.1:22:ecdsa-sha2-nistp256');
    });

    test('bytesToFingerprint converts bytes to colon-hex', () {
      final bytes = Uint8List.fromList([0xab, 0xcd, 0x0f]);
      expect(KnownHost.bytesToFingerprint(bytes), 'ab:cd:0f');
    });
  });

  group('HostKeyChallenge', () {
    test('resolve(true) completes result as true', () async {
      final c = HostKeyChallenge(
        host: 'h', port: 22, keyType: 'k',
        oldFingerprint: 'old', newFingerprint: 'new',
      );
      c.resolve(true);
      expect(await c.result, true);
    });

    test('second resolve is a no-op', () async {
      final c = HostKeyChallenge(
        host: 'h', port: 22, keyType: 'k',
        oldFingerprint: 'old', newFingerprint: 'new',
      );
      c.resolve(true);
      c.resolve(false);
      expect(await c.result, true);
    });
  });
}
