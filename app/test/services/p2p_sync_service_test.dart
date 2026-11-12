import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/p2p_sync_encryption.dart';
import 'package:yourssh/services/p2p_sync_service.dart';

void main() {
  group('P2PSyncService', () {
    late P2PSyncService service;

    setUp(() => service = P2PSyncService());
    tearDown(() => service.stop());

    test('startServer and fetchPayload roundtrip on localhost', () async {
      const payload = 'hello world';
      final url = await service.startServer(
        encryptedPayload: payload,
        hostAddress: '127.0.0.1',
      );
      expect(url, contains('127.0.0.1'));
      expect(url, contains('/sync'));
      final fetched = await service.fetchPayload(url);
      expect(fetched, payload);
    });

    test('server closes after first request', () async {
      const payload = 'data';
      final url = await service.startServer(
        encryptedPayload: payload,
        hostAddress: '127.0.0.1',
      );
      await service.fetchPayload(url);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        () => service.fetchPayload(url),
        throwsA(anything),
      );
    });

    test('getLocalInterfaces returns non-loopback addresses', () async {
      final ifaces = await service.getLocalInterfaces();
      for (final i in ifaces) {
        expect(i.address, isNot(startsWith('127.')));
      }
    });

    test('full encrypt-serve-fetch-decrypt roundtrip', () async {
      final key = P2PSyncEncryption.generateKey();
      const plaintext = '{"hosts":[],"passwords":{}}';
      final encrypted = await P2PSyncEncryption.encrypt(plaintext, key);

      final url = await service.startServer(
        encryptedPayload: encrypted,
        hostAddress: '127.0.0.1',
      );
      final fetched = await service.fetchPayload(url);
      final decrypted = await P2PSyncEncryption.decrypt(fetched, key);
      expect(decrypted, plaintext);
    });

    test('server binds to the chosen interface, not all interfaces', () async {
      await service.startServer(
          encryptedPayload: 'x', hostAddress: '127.0.0.1');
      expect(service.boundAddress?.address, '127.0.0.1');
    });

    test('fetchPayload rejects a body larger than 16 MiB', () async {
      final url = await service.startServer(
        encryptedPayload: 'a' * (16 * 1024 * 1024 + 1),
        hostAddress: '127.0.0.1',
      );
      await expectLater(service.fetchPayload(url), throwsA(anything));
    });

    test('fetchPayload accepts a body of exactly 16 MiB', () async {
      final url = await service.startServer(
        encryptedPayload: 'a' * (16 * 1024 * 1024),
        hostAddress: '127.0.0.1',
      );
      expect((await service.fetchPayload(url)).length, 16 * 1024 * 1024);
    });

    test('fetchPayload rejects non-http schemes and public hosts', () async {
      for (final u in [
        'https://192.168.1.5:1234/sync',
        'file:///etc/passwd',
        'http://8.8.8.8:1234/sync',
        'http://example.com/sync',
      ]) {
        await expectLater(service.fetchPayload(u), throwsA(anything),
            reason: u);
      }
    });

    test('isAllowedSyncUrl allows private, link-local and loopback hosts', () {
      for (final u in [
        'http://10.0.0.2:80/sync',
        'http://172.16.5.1:80/sync',
        'http://172.31.255.1:80/sync',
        'http://192.168.1.9:80/sync',
        'http://169.254.1.1:80/sync',
        'http://127.0.0.1:80/sync',
        'http://[::1]:80/sync',
        'http://[fe80::1]:80/sync',
        'http://[fd00::1]:80/sync',
      ]) {
        expect(P2PSyncService.isAllowedSyncUrl(u), isTrue, reason: u);
      }
      for (final u in [
        'http://172.32.0.1/sync',
        'http://11.0.0.1/sync',
        'http://[2001:db8::1]/sync',
      ]) {
        expect(P2PSyncService.isAllowedSyncUrl(u), isFalse, reason: u);
      }
    });
  });
}
