import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/sync_encryption.dart';
import 'package:yourssh/services/sync_service.dart';

void main() {
  group('SyncService.buildPayload', () {
    test('serialises hosts and passwords into JSON', () async {
      final host = Host(
        id: 'h1',
        label: 'Test',
        host: 'example.com',
        port: 22,
        username: 'user',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final payload = SyncService.buildPayload(
        hosts: [host],
        passwords: {'pw_h1': 'secret'},
      );
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['hosts'], hasLength(1));
      expect((decoded['hosts'][0] as Map)['id'], 'h1');
      expect(decoded['passwords']['pw_h1'], 'secret');
      expect(decoded['updated_at'], isNotNull);
    });
  });

  group('SyncService.shouldPullRemote', () {
    test('returns true when remote is newer', () {
      final remote = DateTime.utc(2026, 5, 29, 12, 0, 0);
      final lastPush = DateTime.utc(2026, 5, 29, 11, 0, 0);
      expect(SyncService.shouldPullRemote(remote, lastPush), true);
    });

    test('returns false when remote is older', () {
      final remote = DateTime.utc(2026, 5, 29, 10, 0, 0);
      final lastPush = DateTime.utc(2026, 5, 29, 11, 0, 0);
      expect(SyncService.shouldPullRemote(remote, lastPush), false);
    });

    test('returns false when lastPush is null (first push wins)', () {
      expect(SyncService.shouldPullRemote(DateTime.utc(2026), null), false);
    });
  });

  group('SyncService encrypt/decrypt roundtrip', () {
    test('buildPayload → encrypt → decrypt → parsePayload is lossless', () async {
      final host = Host(
        id: 'abc',
        label: 'My Server',
        host: '1.2.3.4',
        port: 22,
        username: 'root',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      const syncId = 'ABCDABCDABCD';
      final payload = SyncService.buildPayload(
        hosts: [host],
        passwords: {'pw_abc': 'pass123'},
      );
      final encrypted = await SyncEncryption.encrypt(payload, syncId);
      final decrypted = await SyncEncryption.decrypt(encrypted, syncId);
      final result = SyncService.parsePayload(decrypted);
      expect(result.hosts, hasLength(1));
      expect(result.hosts.first.id, 'abc');
      expect(result.passwords['pw_abc'], 'pass123');
    });
  });
}
