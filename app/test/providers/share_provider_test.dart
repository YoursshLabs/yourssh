import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/share_event.dart';
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

  group('ShareProvider host input authorization', () {
    Future<(ShareProvider, List<String>)> host() async {
      SharedPreferences.setMockInitialValues({});
      final share = ShareProvider(syncProvider: SyncProvider());
      final applied = <String>[];
      share.onGuestInput = applied.add;
      share.handleHostEventForTest(ShareEvent.joinRequest('g1'));
      share.handleHostEventForTest(ShareEvent.joinRequest('g2'));
      return (share, applied);
    }

    test('input from guest without control is ignored', () async {
      final (share, applied) = await host();
      await share.grantControl('g1');
      share.handleHostEventForTest(ShareEvent.input('ls\n', 'g2'));
      expect(applied, isEmpty);
    });

    test('input is ignored when nobody has control', () async {
      final (share, applied) = await host();
      share.handleHostEventForTest(ShareEvent.input('ls\n', 'g1'));
      expect(applied, isEmpty);
    });

    test('input without guestId is ignored', () async {
      final (share, applied) = await host();
      await share.grantControl('g1');
      share.handleHostEventForTest(ShareEvent.input('ls\n', null));
      expect(applied, isEmpty);
    });

    test('input from unknown (never joined) guest is ignored', () async {
      final (share, applied) = await host();
      await share.grantControl('ghost');
      share.handleHostEventForTest(ShareEvent.input('ls\n', 'ghost'));
      expect(applied, isEmpty);
    });

    test('input from the controlling guest is applied', () async {
      final (share, applied) = await host();
      await share.grantControl('g1');
      share.handleHostEventForTest(ShareEvent.input('ls\n', 'g1'));
      expect(applied, ['ls\n']);
    });

    test('input is ignored after control is revoked', () async {
      final (share, applied) = await host();
      await share.grantControl('g1');
      await share.revokeControl();
      share.handleHostEventForTest(ShareEvent.input('ls\n', 'g1'));
      expect(applied, isEmpty);
    });

    test('max 5 guests still enforced', () async {
      final (share, _) = await host();
      for (var i = 3; i <= 7; i++) {
        share.handleHostEventForTest(ShareEvent.joinRequest('g$i'));
      }
      expect(share.guests.length, 5);
    });
  });

  group('ShareProvider guest rejection targeting', () {
    test('rejection for another guest does not end our session', () async {
      SharedPreferences.setMockInitialValues({});
      final share = ShareProvider(syncProvider: SyncProvider());
      share.markGuestForTest();
      share.handleGuestEventForTest(ShareEvent.rejected('full', 'other'), 'me');
      expect(share.isGuest, isTrue);
      share.handleGuestEventForTest(ShareEvent.rejected('full', 'me'), 'me');
      expect(share.isGuest, isFalse);
    });
  });
}
