import 'package:supabase_flutter/supabase_flutter.dart';

enum TestConnectionOutcome { connected, tableNotFound, failed }

class SupabaseService {
  static const migrationSql = '''
create table if not exists sync_data (
  sync_id    text        primary key check (char_length(sync_id) = 12),
  payload    text        not null,
  updated_at timestamptz not null default now()
);
alter table sync_data enable row level security;
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (char_length(sync_id) = 12);''';

  final String _url;
  final String _anonKey;
  SupabaseClient? _clientInstance;

  SupabaseService(this._url, this._anonKey);

  SupabaseClient get _client =>
      _clientInstance ??= SupabaseClient(_url, _anonKey);

  String get url => _url;
  String get anonKey => _anonKey;

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

  Future<String?> fetchPayload(String syncId) async {
    final response = await _client
        .from('sync_data')
        .select('payload')
        .eq('sync_id', syncId)
        .maybeSingle();
    return response?['payload'] as String?;
  }

  Future<DateTime?> fetchUpdatedAt(String syncId) async {
    final response = await _client
        .from('sync_data')
        .select('updated_at')
        .eq('sync_id', syncId)
        .maybeSingle();
    if (response == null) return null;
    return DateTime.parse(response['updated_at'] as String);
  }

  Future<void> upsertPayload(String syncId, String payload) async {
    await _client.from('sync_data').upsert({
      'sync_id': syncId,
      'payload': payload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteSyncRow(String syncId) async {
    await _client.from('sync_data').delete().eq('sync_id', syncId);
  }
}
