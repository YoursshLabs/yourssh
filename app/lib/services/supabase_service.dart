import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final String _url;
  final String _anonKey;
  late final SupabaseClient _client;

  SupabaseService(this._url, this._anonKey) {
    _client = SupabaseClient(_url, _anonKey);
  }

  String get url => _url;
  String get anonKey => _anonKey;

  /// Returns (true, null) on success; (false, errorMessage) on failure.
  Future<(bool, String?)> testConnection() async {
    try {
      await _client.from('sync_data').select('sync_id').limit(1);
      return (true, null);
    } on PostgrestException catch (e) {
      if (e.code == '42P01') {
        return (false, 'Table "sync_data" not found. Run the SQL migration (see docs/SYNC_SETUP.md).');
      }
      return (false, e.message);
    } catch (e) {
      return (false, e.toString());
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
