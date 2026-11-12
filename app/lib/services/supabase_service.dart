import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_code.dart';

enum TestConnectionOutcome { connected, tableNotFound, failed }

class SupabaseService {
  static const migrationSql = '''
create table if not exists sync_data (
  sync_id    text        primary key,
  payload    text        not null,
  updated_at timestamptz not null default now()
);
-- sync_id is a one-way SHA-256 hash of the sync code, not the code itself.
-- Confidentiality and integrity come from client-side AES-GCM keyed by the
-- sync code, which never leaves the devices. Residual risk: anon-key holders
-- can still delete/overwrite rows (a DoS, detected as a decrypt failure).
-- Drop the legacy 12-char sync_id CHECK from older deployments. Safe (no-op)
-- on fresh tables.
alter table sync_data drop constraint if exists sync_data_sync_id_check;
alter table sync_data enable row level security;
drop policy if exists "anon_rw" on sync_data;
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (true);''';

  final String _url;
  final String _anonKey;
  final String _syncCode;
  SupabaseClient? _clientInstance;

  SupabaseService(this._url, this._anonKey, this._syncCode);

  SupabaseClient get _client =>
      _clientInstance ??= SupabaseClient(_url, _anonKey);

  String get url => _url;
  String get anonKey => _anonKey;
  String get syncCode => _syncCode;

  /// Returns (TestConnectionOutcome, errorMessage).
  Future<(TestConnectionOutcome, String?)> testConnection() async {
    try {
      await _client.from('sync_data').select('sync_id').limit(1);
      return (TestConnectionOutcome.connected, null);
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.message.contains('schema cache')) {
        return (TestConnectionOutcome.tableNotFound, null);
      }
      return (TestConnectionOutcome.failed, e.message);
    } catch (e) {
      return (TestConnectionOutcome.failed, e.toString());
    }
  }

  /// Server row id: one-way hash of the sync code (the code itself is the
  /// encryption key input and must never be sent to the server).
  String get rowId => SyncCode.rowId(_syncCode);

  /// Pre-hash deployments keyed the row by the raw sync code.
  String get _legacyId => _syncCode;

  @visibleForTesting
  Future<Map<String, dynamic>?> selectRow(String id, String column) {
    return _client
        .from('sync_data')
        .select(column)
        .eq('sync_id', id)
        .maybeSingle();
  }

  @visibleForTesting
  Future<void> upsertRow(String id, String payload) async {
    await _client.from('sync_data').upsert({
      'sync_id': id,
      'payload': payload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @visibleForTesting
  Future<void> deleteRowById(String id) async {
    await _client.from('sync_data').delete().eq('sync_id', id);
  }

  /// Reads [column] from the derived row, falling back to the legacy raw-code
  /// row for users who have not pushed since the hashed-id change.
  Future<Map<String, dynamic>?> _selectWithLegacyFallback(String column) async {
    return await selectRow(rowId, column) ?? await selectRow(_legacyId, column);
  }

  Future<String?> fetchPayload() async {
    final response = await _selectWithLegacyFallback('payload');
    return response?['payload'] as String?;
  }

  Future<DateTime?> fetchUpdatedAt() async {
    final response = await _selectWithLegacyFallback('updated_at');
    if (response == null) return null;
    return DateTime.parse(response['updated_at'] as String);
  }

  /// Upserts to the derived row id, then best-effort deletes the legacy
  /// raw-code row so the code does not linger in `sync_id`.
  Future<void> upsertPayload(String payload) async {
    await upsertRow(rowId, payload);
    try {
      await deleteRowById(_legacyId);
    } catch (_) {
      // Best effort: a stale legacy row is harmless to this device.
    }
  }

  /// Deletes both the derived row and any legacy raw-code row.
  Future<void> deleteRow() async {
    await deleteRowById(rowId);
    await deleteRowById(_legacyId);
  }
}
