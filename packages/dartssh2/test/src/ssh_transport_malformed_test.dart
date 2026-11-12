import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/kex/kex_dh.dart';
import 'package:dartssh2/src/message/msg_kex.dart';
import 'package:dartssh2/src/message/msg_kex_dh.dart';
import 'package:dartssh2/src/ssh_packet.dart';
import 'package:test/test.dart';

/// A malformed packet from the server must close the transport with an
/// [SSHError] (so `done` / `client.authenticated` complete with an error)
/// instead of throwing out of the socket listener and hanging forever.
void main() {
  SSH_Message_KexInit serverKexInit({
    required List<String> kex,
    String cipher = 'aes128-ctr',
  }) {
    return SSH_Message_KexInit(
      kexAlgorithms: kex,
      serverHostKeyAlgorithms: [SSHHostkeyType.ed25519.name],
      encryptionClientToServer: [cipher],
      encryptionServerToClient: [cipher],
      macClientToServer: [SSHMacType.hmacSha256.name],
      macServerToClient: [SSHMacType.hmacSha256.name],
      compressionClientToServer: const ['none'],
      compressionServerToClient: const ['none'],
      firstKexPacketFollows: false,
    );
  }

  Uint8List version() => Uint8List.fromList('SSH-2.0-test\r\n'.codeUnits);

  Uint8List packet(Uint8List payload) => SSHPacket.pack(payload, align: 8);

  SSHTransport newTransport(_FakeSocket socket) => SSHTransport(
        socket,
        algorithms: SSHAlgorithms(
          kex: [SSHKexType.dhGexSha256],
          hostkey: [SSHHostkeyType.ed25519],
          cipher: [SSHCipherType.aes128ctr],
          mac: [SSHMacType.hmacSha256],
        ),
      );

  Future<void> expectCloses(
    SSHTransport transport,
    Matcher matcher,
  ) async {
    final result = transport.done
        .then<Object?>((_) => 'completed', onError: (Object e) => e);
    expect(
      await result.timeout(const Duration(seconds: 2), onTimeout: () => 'hang'),
      matcher,
    );
  }

  group('SSHTransport malformed packets', () {
    test('packet length 0 closes with SSHError', () async {
      final socket = _FakeSocket();
      final transport = newTransport(socket);
      socket.add(version());
      socket.add(Uint8List(4));
      await expectCloses(transport, isA<SSHError>());
    });

    test('padding longer than packet (negative payload) closes with SSHError',
        () async {
      final socket = _FakeSocket();
      final transport = newTransport(socket);
      socket.add(version());
      final bad = Uint8List(4 + 8);
      ByteData.sublistView(bad).setUint32(0, 8);
      bad[4] = 200;
      socket.add(bad);
      await expectCloses(transport, isA<SSHError>());
    });

    test('KEXINIT without a common algorithm closes with SSHError', () async {
      final socket = _FakeSocket();
      final transport = newTransport(socket);
      socket.add(version());
      socket.add(packet(serverKexInit(kex: ['no-such-kex']).encode()));
      await expectCloses(transport, isA<SSHError>());
    });

    test('empty message payload closes with SSHError', () async {
      final socket = _FakeSocket();
      final transport = newTransport(socket);
      socket.add(version());
      socket.add(packet(Uint8List(0)));
      await expectCloses(transport, isA<SSHError>());
    });
  });

  group('SSHTransport DH group exchange validation', () {
    final goodP = SSHKexDH.group14().p; // 2048-bit prime
    final two = BigInt.two;

    Future<SSHTransport> startGex(_FakeSocket socket) async {
      final transport = newTransport(socket);
      socket.add(version());
      socket.add(
          packet(serverKexInit(kex: [SSHKexType.dhGexSha256.name]).encode()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return transport;
    }

    Future<void> expectGroupRejected(BigInt p, BigInt g) async {
      final socket = _FakeSocket();
      final transport = await startGex(socket);
      socket.add(packet(SSH_Message_KexDH_GexGroup(p: p, g: g).encode()));
      await expectCloses(
        transport,
        isA<SSHHandshakeError>()
            .having((e) => e.message, 'message', contains('DH group')),
      );
    }

    test('rejects p smaller than the requested minimum', () async {
      await expectGroupRejected(BigInt.parse('2').pow(512) - BigInt.one, two);
    });

    test('rejects p larger than the requested maximum', () async {
      await expectGroupRejected(BigInt.two.pow(9000) - BigInt.one, two);
    });

    test('rejects g == 1', () async {
      await expectGroupRejected(goodP, BigInt.one);
    });

    test('rejects g == p - 1', () async {
      await expectGroupRejected(goodP, goodP - BigInt.one);
    });

    for (final entry in <String, BigInt>{
      'f == 0': BigInt.zero,
      'f == 1': BigInt.one,
      'f == p - 1': goodP - BigInt.one,
      'f >= p': goodP,
    }.entries) {
      test('rejects server value ${entry.key}', () async {
        final socket = _FakeSocket();
        final transport = await startGex(socket);
        socket
            .add(packet(SSH_Message_KexDH_GexGroup(p: goodP, g: two).encode()));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        socket.add(packet(SSH_Message_KexDH_GexReply(
          hostPublicKey: Uint8List(8),
          f: entry.value,
          signature: Uint8List(8),
        ).encode()));
        await expectCloses(
          transport,
          isA<SSHHandshakeError>()
              .having((e) => e.message, 'message', contains('DH')),
        );
      });
    }
  });
}

class _FakeSocket implements SSHSocket {
  final _in = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _in.stream;

  @override
  StreamSink<List<int>> get sink => _NullSink();

  @override
  Future<void> get done => _done.future;

  void add(Uint8List data) => _in.add(data);

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
  }
}

class _NullSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> close() async {}
  @override
  Future<void> get done async {}
}
