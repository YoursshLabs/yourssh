import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/sync_code.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isSupabaseConfigured is false on fresh provider', () {
    final p = SyncProvider();
    expect(p.isSupabaseConfigured, isFalse);
    expect(p.supabaseUrl, '');
    expect(p.supabaseAnonKey, '');
  });

  test('setSupabaseConfig updates getters and persists', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('https://x.supabase.co', 'anon-key-abc');
    expect(p.supabaseUrl, 'https://x.supabase.co');
    expect(p.supabaseAnonKey, 'anon-key-abc');
    expect(p.isSupabaseConfigured, isTrue);

    // Verify persisted to prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('supabase_url'), 'https://x.supabase.co');
    expect(prefs.getString('supabase_anon_key'), 'anon-key-abc');
  });

  test('setSupabaseConfig trims whitespace', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('  https://x.supabase.co  ', '  key  ');
    expect(p.supabaseUrl, 'https://x.supabase.co');
    expect(p.supabaseAnonKey, 'key');
  });

  test('isSupabaseConfigured false when only URL is set', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('https://x.supabase.co', '');
    expect(p.isSupabaseConfigured, isFalse);
  });

  test('setSupabaseConfig wins race against concurrent _init() load', () async {
    SharedPreferences.setMockInitialValues({
      'supabase_url': 'stale',
      'supabase_anon_key': 'stale',
    });
    final p = SyncProvider();
    // Call setter immediately without awaiting _init().
    await p.setSupabaseConfig('fresh', 'fresh');
    // Give _init() a chance to complete.
    await Future<void>.delayed(Duration.zero);
    expect(p.supabaseUrl, 'fresh');
    expect(p.supabaseAnonKey, 'fresh');
  });

  test('enabled requires url, anonKey and a sync code', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('https://x.supabase.co', 'anon-key-abc');
    expect(p.isSupabaseConfigured, isTrue);
    expect(p.enabled, isFalse); // no code yet
  });

  test('generateSyncCode sets a valid 12-char code and enables sync', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('https://x.supabase.co', 'anon-key-abc');
    final code = await p.generateSyncCode();
    expect(SyncCode.isValid(code), isTrue);
    expect(p.syncCode, code);
    expect(p.hasSyncCode, isTrue);
    expect(p.enabled, isTrue);
  });

  test('setSyncCode normalizes input', () async {
    final p = SyncProvider();
    await p.setSyncCode('abcd-2345-efgh');
    expect(p.syncCode, 'ABCD2345EFGH');
  });
}
