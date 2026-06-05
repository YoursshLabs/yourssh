import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

SshKeyEntry _keyEntry({String? certPath}) => SshKeyEntry(
      label: 'test-key',
      algorithm: KeyAlgorithm.ed25519,
      publicKey: '',
      privateKeyPath: '/tmp/no-key',
      certificatePath: certPath,
    );

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

  // ── connect() — certificate auth edge cases ──────────────────────────────
  // _resolveIdentities is called BEFORE the TCP socket in connect(), so these
  // throw eagerly without ever touching the network.

  group('connect — certificate auth', () {
    test('no certificatePath throws "No certificate linked"', () async {
      final svc = SshService(StorageService());
      final host = Host(
        label: 'x',
        host: '127.0.0.1',
        port: 1,
        username: 'u',
        authType: AuthType.certificate,
      );

      await expectLater(
        svc.connect(host, keyEntry: _keyEntry(certPath: null)),
        throwsA(predicate((e) =>
            e is Exception && e.toString().contains('No certificate linked'))),
      );
    });

    test('cert file missing throws "Certificate file not found"', () async {
      final svc = SshService(StorageService());
      final host = Host(
        label: 'x',
        host: '127.0.0.1',
        port: 1,
        username: 'u',
        authType: AuthType.certificate,
      );

      await expectLater(
        svc.connect(
            host, keyEntry: _keyEntry(certPath: '/tmp/nonexistent-cert.pub')),
        throwsA(predicate((e) =>
            e is Exception &&
            e.toString().contains('Certificate file not found'))),
      );
    });
  });

  // ── testConnection() — error classification ──────────────────────────────
  // For non-jump hosts testConnection opens the TCP socket first, so
  // SocketException / TimeoutException are the testable failure modes here.

  group('testConnection — error classification', () {
    test('unreachable host → success=false, error="Host unreachable"',
        () async {
      final svc = SshService(StorageService());
      final host = Host(
        label: 'x',
        host: '127.0.0.1',
        port: 1,
        username: 'u',
        authType: AuthType.password,
      );

      final r = await svc.testConnection(host, password: 'pw');

      expect(r.success, isFalse);
      expect(r.error, 'Host unreachable');
      expect(r.latencyMs, 0);
    });
  });

  // ── connect() — privateKey auth ─────────────────────────────────────────
  // Unlike certificate, privateKey silently returns empty identities when the
  // key is missing — identity resolution never throws, so connect() always
  // reaches the TCP layer (and fails there on an unreachable host).

  group('connect — privateKey auth', () {
    test('null keyEntry silently skips key — reaches TCP, throws SocketException',
        () async {
      final svc = SshService(StorageService());
      final host = Host(
        label: 'x',
        host: '127.0.0.1',
        port: 1,
        username: 'u',
        authType: AuthType.privateKey,
      );

      // No keyEntry → _resolveIdentities returns empty list without throwing.
      // connect() proceeds to SSHSocket.connect() → SocketException.
      await expectLater(
        svc.connect(host),
        throwsA(isA<SocketException>()),
      );
    });

    test('missing key file silently skips key — reaches TCP, throws SocketException',
        () async {
      final svc = SshService(StorageService());
      final host = Host(
        label: 'x',
        host: '127.0.0.1',
        port: 1,
        username: 'u',
        authType: AuthType.privateKey,
      );

      // File doesn't exist → _resolveIdentities returns empty list without throwing.
      await expectLater(
        svc.connect(host, keyEntry: _keyEntry()),
        throwsA(isA<SocketException>()),
      );
    });
  });

  // ── connect() — agent auth ────────────────────────────────────────────────
  // _resolveIdentities calls SystemAgentProxy.connect() BEFORE the TCP socket,
  // so when no SSH agent is running the method throws SSHAgentUnavailableException
  // before any network I/O.

  group('connect — agent auth', () {
    test(
      'no SSH agent → throws SSHAgentUnavailableException before TCP',
      () async {
        final svc = SshService(StorageService());
        final host = Host(
          label: 'x',
          host: '127.0.0.1',
          port: 1,
          username: 'u',
          authType: AuthType.agent,
        );

        await expectLater(
          svc.connect(host),
          throwsA(isA<SSHAgentUnavailableException>()),
        );
      },
      // Only run when SSH_AUTH_SOCK is not set; with a live agent the test
      // would instead try TCP and throw SocketException.
      skip: Platform.environment.containsKey('SSH_AUTH_SOCK')
          ? 'SSH_AUTH_SOCK is set — agent is available in this environment'
          : null,
    );
  });

  // ── State queries and no-op safety ───────────────────────────────────────

  group('SshService state', () {
    test('isConnected returns false for unknown host', () {
      final svc = SshService(StorageService());
      expect(svc.isConnected('no-such-host'), isFalse);
    });

    test('connectedHostIds is empty when no connections', () {
      final svc = SshService(StorageService());
      expect(svc.connectedHostIds, isEmpty);
    });

    test('disconnect on unknown host does not throw', () {
      final svc = SshService(StorageService());
      expect(() => svc.disconnect('no-such-host'), returnsNormally);
    });

    test('sendInput reports failure for a session without a shell', () {
      // Callers (snippets, plugins) show success feedback — a silent no-op
      // here meant "Sent" toasts for input that never reached the server.
      final svc = SshService(StorageService());
      expect(svc.sendInput('no-such-session', 'hello'), isFalse);
    });

    test('measureLatency returns null for unknown host', () async {
      final svc = SshService(StorageService());
      expect(await svc.measureLatency('no-such-host'), isNull);
    });

    test('disconnectSession on unknown session does not throw', () {
      final svc = SshService(StorageService());
      expect(
          () => svc.disconnectSession('no-such-session'), returnsNormally);
    });
  });

  group('ensureClient', () {
    test('throws StateError when not connected and no verifier wired', () async {
      final svc = SshService(StorageService());
      final host = Host(label: 'x', host: '127.0.0.1', port: 1, username: 'u');
      expect(() => svc.ensureClient(host), throwsStateError);
    });
  });
}
