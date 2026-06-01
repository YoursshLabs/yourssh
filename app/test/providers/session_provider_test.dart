import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Host _makeHost(String id) => Host(
  id: id, label: id, host: '$id.example.com', port: 22, username: 'user',
);

SshSession _makeSession(String hostId) =>
    SshSession(host: _makeHost(hostId));

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
      provider = SessionProvider(SshService(StorageService()), TabMetadataService());
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

    test('loadMetadata applied to session on connect (mocked via SharedPreferences)', () async {
      SharedPreferences.setMockInitialValues({
        'tab_meta_h-load': jsonEncode({
          'label': 'saved-label',
          'color': '#22c55e',
          'pinned': true,
        }),
      });
      final p = SessionProvider(SshService(StorageService()), TabMetadataService());
      final host = Host(
        id: 'h-load',
        label: 'Test',
        host: '127.0.0.1',
        port: 1,
        username: 'user',
      );
      // SSH will fail (no real server) but metadata is loaded before _doConnect.
      // connect() catches all SSH exceptions internally, so await completes cleanly.
      await p.connect(host);
      final session = p.sessions.first;
      expect(session.customLabel, 'saved-label');
      expect(session.colorTag, '#22c55e');
      expect(session.isPinned, isTrue);
      p.dispose();
    });
  });

  group('tab metadata mutations', () {
    late SessionProvider p;

    setUp(() {
      p = SessionProvider(SshService(StorageService()), TabMetadataService());
      p.addWatchSession(_makeSession('h1'));
      p.addWatchSession(_makeSession('h2'));
      p.addWatchSession(_makeSession('h3'));
    });

    tearDown(() => p.dispose());

    test('renameSession sets customLabel', () async {
      p.renameSession(p.sessions.first.id, 'renamed');
      expect(p.sessions.first.customLabel, 'renamed');
    });

    test('renameSession with null clears label', () async {
      p.renameSession(p.sessions.first.id, 'x');
      p.renameSession(p.sessions.first.id, null);
      expect(p.sessions.first.customLabel, isNull);
    });

    test('setSessionColor sets colorTag', () async {
      p.setSessionColor(p.sessions.first.id, '#ef4444');
      expect(p.sessions.first.colorTag, '#ef4444');
    });

    test('setSessionColor with null clears color', () async {
      p.setSessionColor(p.sessions.first.id, '#ef4444');
      p.setSessionColor(p.sessions.first.id, null);
      expect(p.sessions.first.colorTag, isNull);
    });

    test('togglePin pins and moves session to front', () {
      final third = p.sessions[2];
      p.togglePin(third.id);
      expect(p.sessions.first.id, third.id);
      expect(p.sessions.first.isPinned, isTrue);
    });

    test('togglePin twice unpins and session leaves front', () {
      final third = p.sessions[2];
      p.togglePin(third.id);
      p.togglePin(third.id);
      expect(p.sessions.first.isPinned, isFalse);
    });

    test('reorderSessionItem moves unpinned tab', () {
      final h1Id = p.sessions[0].id;
      // onReorderItem already subtracts 1 when moving forward: pass 1 directly.
      // Result: [h2, h1, h3]
      p.reorderSessionItem(0, 1);
      expect(p.sessions[1].id, h1Id);
    });

    test('reorderSessionItem: unpinned tab cannot be dragged into pinned zone', () {
      p.togglePin(p.sessions[0].id);
      // sessions: [h1(pinned), h2, h3]
      p.reorderSessionItem(1, 0);
      expect(p.sessions[0].isPinned, isTrue);
      expect(p.sessions[1].isPinned, isFalse);
    });

    test('reorderSessionItem: pinned tab cannot be dragged into unpinned zone', () {
      p.togglePin(p.sessions[0].id);
      // sessions: [h1(pinned), h2, h3]
      final h1Id = p.sessions[0].id;
      // onReorderItem subtracts 1 when moving forward: 3-1=2
      p.reorderSessionItem(0, 2);
      expect(p.sessions[0].id, h1Id);
      expect(p.sessions[0].isPinned, isTrue);
    });

    test('mutating one tab mirrors metadata onto sibling tabs of the same host',
        () {
      final p2 =
          SessionProvider(SshService(StorageService()), TabMetadataService());
      p2.addWatchSession(_makeSession('dup'));
      p2.addWatchSession(_makeSession('dup'));
      final a = p2.sessions[0];
      final b = p2.sessions[1];
      expect(a.host.id, b.host.id);

      p2.renameSession(a.id, 'shared');
      p2.setSessionColor(a.id, '#ef4444');
      // Per-host metadata: the sibling tab reflects the same label and color
      // instead of silently diverging and stomping the persisted record.
      expect(b.customLabel, 'shared');
      expect(b.colorTag, '#ef4444');
      p2.dispose();
    });
  });
}
