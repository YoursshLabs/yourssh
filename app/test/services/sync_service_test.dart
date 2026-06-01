import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/supabase_service.dart';
import 'package:yourssh/services/sync_encryption.dart';
import 'package:yourssh/services/sync_service.dart';

class _ThrowingSupabase extends SupabaseService {
  _ThrowingSupabase()
      : super('https://test.supabase.co', 'test-anon-key', 'ABCD2345EFGH');

  @override
  Future<void> deleteRow() async => throw Exception('network error');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('returns true when lastPush is null (new device always pulls remote)', () {
      expect(SyncService.shouldPullRemote(DateTime.utc(2026), null), true);
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
      const code = 'ABCD2345EFGH';
      final payload = SyncService.buildPayload(
        hosts: [host],
        passwords: {'pw_abc': 'pass123'},
      );
      final encrypted = await SyncEncryption.encrypt(payload, code);
      final decrypted = await SyncEncryption.decrypt(encrypted, code);
      final result = SyncService.parsePayload(decrypted);
      expect(result.hosts, hasLength(1));
      expect(result.hosts.first.id, 'abc');
      expect(result.passwords['pw_abc'], 'pass123');
    });
  });

  group('SyncService.disableAndDelete', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'sync_pending_push': true,
        'sync_last_push_at': '2026-01-01T00:00:00.000Z',
      });
    });

    test('clears local prefs and disables sync even when remote delete throws', () async {
      final syncProvider = SyncProvider();
      await syncProvider.setSupabaseConfig('https://test.supabase.co', 'test-anon-key');
      final service = SyncService(syncProvider)
        ..cachedSupabase = _ThrowingSupabase();
      await service.disableAndDelete();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sync_pending_push'), isNull);
      expect(prefs.getString('sync_last_push_at'), isNull);
      expect(syncProvider.enabled, false);

      syncProvider.dispose();
    });
  });
}
