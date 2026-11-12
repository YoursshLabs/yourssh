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

class _FakeRemote extends SupabaseService {
  _FakeRemote(String code, this.encrypted, this.serverUpdatedAt)
      : super('https://test.supabase.co', 'test-anon-key', code);
  final String encrypted;
  final DateTime serverUpdatedAt;

  @override
  Future<DateTime?> fetchUpdatedAt() async => serverUpdatedAt;

  @override
  Future<String?> fetchPayload() async => encrypted;
}

String _payloadAt(DateTime t) => jsonEncode({
      'hosts': <dynamic>[],
      'passwords': <String, String>{},
      'updated_at': t.toUtc().toIso8601String(),
    });

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

  group('SyncService.pull anti-rollback', () {
    const code = 'ABCD2345EFGH';

    Future<(SyncService, SyncProvider)> build(
        DateTime innerAt, Map<String, Object> prefsInit) async {
      SharedPreferences.setMockInitialValues(prefsInit);
      final p = SyncProvider();
      await p.setSupabaseConfig('https://test.supabase.co', 'test-anon-key');
      await p.setSyncCode(code);
      final enc = await SyncEncryption.encrypt(_payloadAt(innerAt), code);
      // Server-supplied updated_at is fresh (attacker-controlled).
      final svc = SyncService(p)
        ..cachedSupabase = _FakeRemote(code, enc, DateTime.now().toUtc());
      return (svc, p);
    }

    test('rejects a replayed payload older than last push', () async {
      final (svc, p) = await build(DateTime.utc(2026, 1, 1),
          {'sync_last_push_at': '2026-03-01T00:00:00.000Z'});
      expect(await svc.pull(), isNull);
      expect(p.status, SyncStatus.synced);
      expect(p.error, isNull);
      p.dispose();
    });

    test('rejects a payload not newer than last applied', () async {
      final (svc, p) = await build(DateTime.utc(2026, 1, 1),
          {'sync_last_applied_at': '2026-02-01T00:00:00.000Z'});
      expect(await svc.pull(), isNull);
      expect(p.error, isNull);
      p.dispose();
    });

    test('accepts a newer payload and records last applied', () async {
      final (svc, p) = await build(DateTime.utc(2026, 5, 1),
          {'sync_last_push_at': '2026-03-01T00:00:00.000Z'});
      final r = await svc.pull();
      expect(r, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_last_applied_at'),
          DateTime.utc(2026, 5, 1).toIso8601String());
      p.dispose();
    });

    test('new device (no push, no applied) accepts', () async {
      final (svc, p) = await build(DateTime.utc(2020), {});
      expect(await svc.pull(), isNotNull);
      p.dispose();
    });
  });
}
