import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

Uint8List _agentMsg(List<int> body) {
  final header = Uint8List(4);
  ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
  return Uint8List.fromList([...header, ...body]);
}

List<int> _strField(List<int> data) {
  final len = Uint8List(4);
  ByteData.view(len.buffer).setUint32(0, data.length, Endian.big);
  return [...len, ...data];
}

void main() {
  group('SystemAgentProxy', () {
    late ServerSocket server;
    late String socketPath;

    setUp(() async {
      socketPath = '/tmp/yourssh_test_${DateTime.now().millisecondsSinceEpoch}.sock';
      server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
    });

    tearDown(() async {
      await server.close();
      final f = File(socketPath);
      if (await f.exists()) await f.delete();
    });

    test('getIdentities returns one AgentKeyPair with correct type', () async {
      final algName = utf8.encode('ssh-ed25519');
      final keyBlob = Uint8List.fromList([
        ..._strField(algName),
        ..._strField(List.filled(32, 0xAB)),
      ]);

      unawaited(server.first.then((client) {
        client.listen((_) {
          final nkeys = Uint8List(4);
          ByteData.view(nkeys.buffer).setUint32(0, 1, Endian.big);
          final response = [
            12,
            ...nkeys,
            ..._strField(keyBlob),
            ..._strField(utf8.encode('test-key')),
          ];
          client.add(_agentMsg(response));
        });
      }));

      final proxy = await SystemAgentProxy.connectTo(socketPath);
      final identities = await proxy.getIdentities();

      expect(identities.length, 1);
      expect(identities[0].type, 'ssh-ed25519');
      expect(identities[0].toPublicKey().encode(), equals(keyBlob));

      await proxy.close();
    });

    test('getIdentities returns empty list when agent has no keys', () async {
      unawaited(server.first.then((client) {
        client.listen((_) {
          final nkeys = Uint8List(4);
          final response = [12, ...nkeys];
          client.add(_agentMsg(response));
        });
      }));

      final proxy = await SystemAgentProxy.connectTo(socketPath);
      final identities = await proxy.getIdentities();
      expect(identities, isEmpty);
      await proxy.close();
    });

    test('connectTo throws SSHAgentUnavailableException for missing socket', () async {
      await expectLater(
        SystemAgentProxy.connectTo('/tmp/nonexistent_socket_xyz.sock'),
        throwsA(isA<SSHAgentUnavailableException>()),
      );
    });

    test('_AgentKeyPair.signAsync sends type 13 and receives type 14', () async {
      final algName = utf8.encode('ssh-ed25519');
      final keyBlob = Uint8List.fromList([
        ..._strField(algName),
        ..._strField(List.filled(32, 0xAB)),
      ]);
      final fakeSignature = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

      unawaited(server.first.then((client) {
        // First request: identities
        var requestCount = 0;
        client.listen((data) {
          requestCount++;
          if (requestCount == 1) {
            // Respond to REQUEST_IDENTITIES (11) with one key
            final nkeys = Uint8List(4);
            ByteData.view(nkeys.buffer).setUint32(0, 1, Endian.big);
            final response = [
              12, ...nkeys,
              ..._strField(keyBlob),
              ..._strField(utf8.encode('test-key')),
            ];
            client.add(_agentMsg(response));
          } else {
            // Respond to SIGN_REQUEST (13) with SIGN_RESPONSE (14)
            final response = [14, ..._strField(fakeSignature)];
            client.add(_agentMsg(response));
          }
        });
      }));

      final proxy = await SystemAgentProxy.connectTo(socketPath);
      final identities = await proxy.getIdentities();
      expect(identities.length, 1);

      final challenge = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final sig = await identities[0].signAsync(challenge);
      expect(sig.encode(), equals(fakeSignature));

      await proxy.close();
    });
  },
      // The fake agent binds a Unix domain socket — not available on the
      // Windows CI runner (the real Windows agent uses a named pipe).
      skip: Platform.isWindows
          ? 'Unix domain sockets unavailable on Windows'
          : false);
}
