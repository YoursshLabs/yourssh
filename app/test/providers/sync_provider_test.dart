import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncProvider', () {
    late SyncProvider provider;

    setUp(() {
      provider = SyncProvider();
    });

    tearDown(() => provider.dispose());

    test('initial state: disabled, idle, no error', () {
      expect(provider.enabled, false);
      expect(provider.status, SyncStatus.idle);
      expect(provider.error, isNull);
      expect(provider.lastSynced, isNull);
    });

    test('enabled requires Supabase config and a sync code', () async {
      expect(provider.enabled, false);
      await provider.setSupabaseConfig('https://x.supabase.co', 'key');
      expect(provider.enabled, false); // config set, but no sync code yet
      await provider.setSyncCode('ABCD2345EFGH');
      expect(provider.enabled, true);
      await provider.clearSupabaseConfig();
      expect(provider.enabled, false);
    });

    test('setStatus notifies listeners', () {
      var count = 0;
      provider.addListener(() => count++);
      provider.setStatus(SyncStatus.syncing);
      provider.setStatus(SyncStatus.synced);
      expect(count, 2);
    });

    test('setError stores error message and sets error status', () {
      provider.setError('network failure');
      expect(provider.status, SyncStatus.error);
      expect(provider.error, 'network failure');
    });

    test('setStatus(synced) clears error and sets lastSynced', () {
      provider.setError('old error');
      provider.setStatus(SyncStatus.synced);
      expect(provider.error, isNull);
      expect(provider.lastSynced, isNotNull);
    });
  });
}
