import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // Use dart-define at build time: --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static Future<void> initialize() async {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _anonKey);
  }

  SupabaseClient get _client => Supabase.instance.client;

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
