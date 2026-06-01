import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  group('SessionProvider', () {
    late SessionProvider provider;

    setUp(() {
      provider = SessionProvider(SshService(StorageService()));
    });

    tearDown(() => provider.dispose());

    test('starts empty', () {
      expect(provider.sessions, isEmpty);
      expect(provider.activeSession, isNull);
    });

    test('hostForSession returns null for unknown id', () {
      expect(provider.hostForSession('does-not-exist'), isNull);
    });

    test('closeSession on unknown id is a no-op', () {
      // Must not throw; sessions list stays empty.
      provider.closeSession('does-not-exist');
      expect(provider.sessions, isEmpty);
    });

    test('activateNext / activatePrev are no-ops when empty', () {
      // Used to throw StateError on iteration before the empty-guard was added.
      provider.activateNext();
      provider.activatePrev();
      expect(provider.activeSession, isNull);
    });

    test('dispose is safe to call multiple times', () {
      provider.dispose();
      // Second dispose() must not throw.
      expect(() => provider.dispose(), returnsNormally);
    });

    test('closeSession cancels countdown timer without throwing', () async {
      final host = Host(
        label: 'test',
        host: '127.0.0.1',
        port: 1,
        username: 'x',
      );
      provider.autoReconnectEnabled = () => true;
      provider.reconnectAttempts = () => 0; // unlimited

      final future = provider.connect(host);
      await Future<void>.delayed(Duration.zero);

      expect(provider.sessions, isNotEmpty);

      provider.closeSession(provider.sessions.first.id);
      expect(provider.sessions, isEmpty);

      await expectLater(future, completes);
    });

    test('unlimited reconnect: session stays connecting after first failure', () async {
      final host = Host(
        label: 'unreachable',
        host: '127.0.0.1',
        port: 1,
        username: 'x',
      );
      provider.autoReconnectEnabled = () => true;
      provider.reconnectAttempts = () => 0; // unlimited

      final future = provider.connect(host);
      await expectLater(future, completes);

      expect(provider.sessions, isNotEmpty);
      expect(provider.sessions.first.status, SessionStatus.connecting);

      provider.closeSession(provider.sessions.first.id);
    });

    test('dispose during in-flight connect does not throw', () async {
      // Kick off a connect; immediately dispose. The connect future resolves
      // later (TCP failure) but our _safeNotify guard prevents notifyListeners
      // on the disposed provider.
      final host = Host(label: 'unreachable', host: '127.0.0.1', port: 1, username: 'x');
      final future = provider.connect(host);
      provider.dispose();
      // Connect should not throw out; it surfaces failure via session state.
      await expectLater(future, completes);
    });
  });
}
