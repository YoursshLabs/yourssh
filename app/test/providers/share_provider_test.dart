import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/share_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShareProvider.canShare', () {
    test('returns false when Supabase is not configured', () async {
      SharedPreferences.setMockInitialValues({});
      final sync = SyncProvider();
      await Future.delayed(Duration.zero);
      final share = ShareProvider(syncProvider: sync);
      expect(share.canShare, isFalse);
    });

    test('returns true when Supabase is configured', () async {
      SharedPreferences.setMockInitialValues({
        'supabase_url': 'https://test.supabase.co',
        'supabase_anon_key': 'test-anon-key',
      });
      final sync = SyncProvider();
      await Future.delayed(Duration.zero);
      final share = ShareProvider(syncProvider: sync);
      expect(share.canShare, isTrue);
    });
  });

  group('ShareProvider initial state', () {
    test('starts not sharing and not as guest', () async {
      SharedPreferences.setMockInitialValues({});
      final sync = SyncProvider();
      final share = ShareProvider(syncProvider: sync);
      expect(share.isSharing, isFalse);
      expect(share.isGuest, isFalse);
      expect(share.shareCode, isNull);
      expect(share.guests, isEmpty);
      expect(share.controlledBy, isNull);
    });
  });
}
