import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/agent_forwarding_handler.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

import '../helpers/agent_protocol.dart';

void main() {
  group('AgentForwardingHandler', () {
    late ServerSocket server;
    late String socketPath;

    setUp(() async {
      socketPath =
          '/tmp/yourssh_fwd_test_${DateTime.now().microsecondsSinceEpoch}.sock';
      server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      // Fake system agent: answer every request on every connection with an
      // empty IDENTITIES_ANSWER (type 12, count 0).
      server.listen((client) {
        client.listen((_) {
          client.add(agentMsg([12, 0, 0, 0, 0]));
        });
      });
    });

    tearDown(() async {
      await server.close();
      final f = File(socketPath);
      if (await f.exists()) await f.delete();
    });

    test('relays request to the system agent and returns its response',
        () async {
      var loaderCalls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () => SystemAgentProxy.connectTo(socketPath),
        loadKeychainIdentities: () async {
          loaderCalls++;
          return const <SSHKeyPair>[];
        },
      );

      final response =
          await handler.handleRequest(Uint8List.fromList([11]));
      expect(response, equals([12, 0, 0, 0, 0]));
      // System agent answered — Keychain fallback never touched.
      expect(loaderCalls, 0);
    });

    test('falls back to Keychain agent when system agent is unavailable, '
        'and caches the fallback across requests', () async {
      var loaderCalls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () async =>
            throw const SSHAgentUnavailableException('none'),
        loadKeychainIdentities: () async {
          loaderCalls++;
          return const <SSHKeyPair>[];
        },
      );

      // SSHKeyPairAgent with zero keys answers REQUEST_IDENTITIES (11)
      // with IDENTITIES_ANSWER (12) and count 0.
      final r1 = await handler.handleRequest(Uint8List.fromList([11]));
      expect(r1[0], SSHAgentProtocol.identitiesAnswer);
      final r2 = await handler.handleRequest(Uint8List.fromList([11]));
      expect(r2[0], SSHAgentProtocol.identitiesAnswer);
      // Built once, reused.
      expect(loaderCalls, 1);
    });

    test('retries the system agent on each request (recovers mid-session)',
        () async {
      var attempt = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () {
          attempt++;
          if (attempt == 1) {
            throw const SSHAgentUnavailableException('not yet');
          }
          return SystemAgentProxy.connectTo(socketPath);
        },
        loadKeychainIdentities: () async => const <SSHKeyPair>[],
      );

      await handler.handleRequest(Uint8List.fromList([11])); // fallback
      final response =
          await handler.handleRequest(Uint8List.fromList([11]));
      // Second request reached the fake system agent (raw relay shape).
      expect(response, equals([12, 0, 0, 0, 0]));
      expect(attempt, 2);
    });

    test('propagates failures that happen after connect succeeded', () async {
      // Agent accepts the connection then dies before replying.
      await server.close();
      server = await ServerSocket.bind(
        InternetAddress('$socketPath.dead', type: InternetAddressType.unix),
        0,
      );
      addTearDown(() async {
        final f = File('$socketPath.dead');
        if (await f.exists()) await f.delete();
      });
      server.listen((client) {
        client.destroy(); // connect OK, then immediate close
      });

      var loaderCalls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () =>
            SystemAgentProxy.connectTo('$socketPath.dead'),
        loadKeychainIdentities: () async {
          loaderCalls++;
          return const <SSHKeyPair>[];
        },
      );

      await expectLater(
        handler.handleRequest(Uint8List.fromList([11])),
        throwsA(isA<SSHAgentUnavailableException>()),
      );
      // Post-connect failure must NOT switch key sources mid-request.
      expect(loaderCalls, 0);
    });
  },
      // Fake agent binds a Unix domain socket — unavailable on Windows CI.
      skip: Platform.isWindows
          ? 'Unix domain sockets unavailable on Windows'
          : false);

  group('loadKeychainKeyPairs', () {
    SshKeyEntry entry(String path) => SshKeyEntry(
          label: 'k',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: '',
          privateKeyPath: path,
        );

    test('loads an unencrypted key', () async {
      final pairs = await loadKeychainKeyPairs(
        [entry('test/fixtures/keys/id_ed25519')],
        (_) async => null,
      );
      expect(pairs, hasLength(1));
      expect(pairs.single.type, 'ssh-ed25519');
    });

    test('loads an encrypted key using the stored passphrase', () async {
      final pairs = await loadKeychainKeyPairs(
        [entry('test/fixtures/keys/id_ed25519_enc')],
        (_) async => 'test-passphrase',
      );
      expect(pairs, hasLength(1));
    });

    test('skips entries that cannot load, keeps the rest', () async {
      final dir = await Directory.systemTemp.createTemp('yourssh_keys');
      addTearDown(() => dir.delete(recursive: true));
      final garbage = File('${dir.path}/garbage')
        ..writeAsStringSync('not a pem');

      final pairs = await loadKeychainKeyPairs(
        [
          entry('${dir.path}/missing'), // file does not exist
          entry(garbage.path), // unparseable
          entry('test/fixtures/keys/id_ed25519_enc'), // wrong passphrase
          entry('test/fixtures/keys/id_ed25519'), // good
        ],
        (_) async => null,
      );
      expect(pairs, hasLength(1));
      expect(pairs.single.type, 'ssh-ed25519');
    });
  });
}
