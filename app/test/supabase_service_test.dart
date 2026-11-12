import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/supabase_service.dart';
import 'package:yourssh/services/sync_code.dart';

class _FakeRows extends SupabaseService {
  _FakeRows(String code) : super('https://x.supabase.co', 'k', code);
  final rows = <String, Map<String, String>>{};
  final calls = <String>[];
  bool throwOnDelete = false;

  @override
  Future<Map<String, dynamic>?> selectRow(String id, String column) async {
    calls.add('select:$id');
    final r = rows[id];
    return r == null ? null : {column: r[column]};
  }

  @override
  Future<void> upsertRow(String id, String payload) async {
    calls.add('upsert:$id');
    rows[id] = {'payload': payload, 'updated_at': '2026-01-01T00:00:00Z'};
  }

  @override
  Future<void> deleteRowById(String id) async {
    calls.add('delete:$id');
    if (throwOnDelete) throw Exception('boom');
    rows.remove(id);
  }
}

void main() {
  test('stores url, anonKey and syncCode via constructor', () {
    final svc =
        SupabaseService('https://abc.supabase.co', 'anon-key-123', 'ABCD2345EFGH');
    expect(svc.url, 'https://abc.supabase.co');
    expect(svc.anonKey, 'anon-key-123');
    expect(svc.syncCode, 'ABCD2345EFGH');
  });

  test('migrationSql contains sync_data table definition', () {
    expect(SupabaseService.migrationSql, contains('sync_data'));
    expect(SupabaseService.migrationSql, contains('row level security'));
  });

  group('row id', () {
    const code = 'ABCD2345EFGH';
    final derived = SyncCode.rowId(code);

    test('rowId getter is the derived id, never the raw code', () {
      expect(SupabaseService('u', 'k', code).rowId, derived);
    });

    test('fetch reads the derived id first', () async {
      final f = _FakeRows(code)..rows[derived] = {'payload': 'new', 'updated_at': '2026-01-01T00:00:00Z'};
      expect(await f.fetchPayload(), 'new');
      expect(f.calls, ['select:$derived']);
    });

    test('fetch falls back to the legacy raw-code row', () async {
      final f = _FakeRows(code)..rows[code] = {'payload': 'old', 'updated_at': '2026-01-01T00:00:00Z'};
      expect(await f.fetchPayload(), 'old');
      expect(await f.fetchUpdatedAt(), DateTime.utc(2026));
      expect(f.calls.first, 'select:$derived');
      expect(f.calls, contains('select:$code'));
    });

    test('upsert writes the derived id then deletes the legacy row', () async {
      final f = _FakeRows(code)..rows[code] = {'payload': 'old', 'updated_at': 'x'};
      await f.upsertPayload('enc');
      expect(f.calls, ['upsert:$derived', 'delete:$code']);
      expect(f.rows.keys, [derived]);
    });

    test('legacy delete failure is swallowed', () async {
      final f = _FakeRows(code)..throwOnDelete = true;
      await f.upsertPayload('enc');
      expect(f.rows.containsKey(derived), isTrue);
    });

    test('deleteRow removes both derived and legacy rows', () async {
      final f = _FakeRows(code)
        ..rows[code] = {'payload': 'a', 'updated_at': 'x'}
        ..rows[derived] = {'payload': 'b', 'updated_at': 'x'};
      await f.deleteRow();
      expect(f.rows, isEmpty);
    });

    test('raw code is never used as the target of an upsert', () async {
      final f = _FakeRows(code);
      await f.upsertPayload('enc');
      expect(f.calls.where((c) => c == 'upsert:$code'), isEmpty);
    });
  });
}
