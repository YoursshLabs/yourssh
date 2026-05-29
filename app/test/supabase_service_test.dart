import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/supabase_service.dart';

void main() {
  test('stores url and anonKey via constructor', () {
    final svc = SupabaseService('https://abc.supabase.co', 'anon-key-123');
    expect(svc.url, 'https://abc.supabase.co');
    expect(svc.anonKey, 'anon-key-123');
  });
}
