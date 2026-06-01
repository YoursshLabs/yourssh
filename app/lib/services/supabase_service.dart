import 'package:supabase_flutter/supabase_flutter.dart';

enum TestConnectionOutcome { connected, tableNotFound, failed }

class SupabaseService {
  static const migrationSql = '''
create table if not exists sync_data (
  sync_id    text        primary key,
  payload    text        not null,
  updated_at timestamptz not null default now()
);
-- Drop the legacy 12-char sync_id CHECK from older deployments; rows are now
-- keyed by the client's sync code. Safe (no-op) on fresh tables.
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

  Future<String?> fetchPayload() async {
    final response = await _client
        .from('sync_data')
        .select('payload')
        .eq('sync_id', _syncCode)
        .maybeSingle();
    return response?['payload'] as String?;
  }

  Future<DateTime?> fetchUpdatedAt() async {
    final response = await _client
        .from('sync_data')
        .select('updated_at')
        .eq('sync_id', _syncCode)
        .maybeSingle();
    if (response == null) return null;
    return DateTime.parse(response['updated_at'] as String);
  }

  Future<void> upsertPayload(String payload) async {
    await _client.from('sync_data').upsert({
      'sync_id': _syncCode,
      'payload': payload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteRow() async {
    await _client.from('sync_data').delete().eq('sync_id', _syncCode);
  }
}
