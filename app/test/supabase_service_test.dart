import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/supabase_service.dart';

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
}
