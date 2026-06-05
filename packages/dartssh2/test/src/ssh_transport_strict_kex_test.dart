import 'dart:async';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_kex.dart';
import 'package:dartssh2/src/ssh_packet.dart';
import 'package:test/test.dart';

/// Tests for the strict key exchange extension (kex-strict-c/s-v00@openssh.com)
/// that mitigates CVE-2023-48795 ("Terrapin attack").
void main() {
  final transportLibrary = reflectClass(SSHTransport).owner as LibraryMirror;
  final packetLibrary = reflectClass(SSHPacketSN).owner as LibraryMirror;
  Symbol privateSymbol(String name) =>
      MirrorSystem.getSymbol(name, transportLibrary);
  Symbol packetPrivateSymbol(String name) =>
      MirrorSystem.getSymbol(name, packetLibrary);
  void setPrivate(SSHTransport transport, String field, Object? value) {
    reflect(transport).setField(privateSymbol(field), value);
  }

  T getPrivate<T>(SSHTransport transport, String field) {
    return reflect(transport).getField(privateSymbol(field)).reflectee as T;
  }

  void setSequenceValue(SSHTransport transport, String field, int value) {
    final sequence =
        reflect(transport).getField(privateSymbol(field)).reflectee;
    reflect(sequence).setField(packetPrivateSymbol('_value'), value);
  }

  int getSequenceValue(SSHTransport transport, String field) {
    final sequence =
        reflect(transport).getField(privateSymbol(field)).reflectee;
    return reflect(sequence)
        .getField(packetPrivateSymbol('_value'))
        .reflectee as int;
  }

  /// Extracts the payload of a cleartext SSH packet captured on the wire.
  Uint8List packetPayload(Uint8List packet) {
    final packetLength = SSHPacket.readPacketLength(packet);
    final paddingLength = SSHPacket.readPaddingLength(packet);
    return Uint8List.sublistView(packet, 5, 4 + packetLength - paddingLength);
  }

  SSH_Message_KexInit buildKexInit({required List<String> kexAlgorithms}) {
    return SSH_Message_KexInit(
      kexAlgorithms: kexAlgorithms,
      serverHostKeyAlgorithms: [SSHHostkeyType.ed25519.name],
      encryptionClientToServer: [SSHCipherType.aes128ctr.name],
      encryptionServerToClient: [SSHCipherType.aes128ctr.name],
      macClientToServer: [SSHMacType.hmacSha256.name],
      macServerToClient: [SSHMacType.hmacSha256.name],
      compressionClientToServer: const ['none'],
      compressionServerToClient: const ['none'],
      firstKexPacketFollows: false,
    );
  }

  group('SSHTransport strict kex (CVE-2023-48795)', () {
    test('client KEXINIT advertises kex-strict-c-v00@openssh.com', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      // packets[0] is the version string, packets[1] is KEXINIT.
      expect(socket.packets, hasLength(greaterThanOrEqualTo(2)));
      final kexInit = SSH_Message_KexInit.decode(
        packetPayload(socket.packets[1]),
      );
      expect(kexInit.kexAlgorithms, contains('kex-strict-c-v00@openssh.com'));
      expect(
        kexInit.kexAlgorithms,
        isNot(contains('kex-strict-s-v00@openssh.com')),
      );

      transport.close();
    });

    test('server KEXINIT advertises kex-strict-s-v00@openssh.com', () async {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket, isServer: true);

      socket.addIncomingBytes(
        Uint8List.fromList('SSH-2.0-test\r\n'.codeUnits),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(socket.packets, hasLength(greaterThanOrEqualTo(2)));
      final kexInit = SSH_Message_KexInit.decode(
        packetPayload(socket.packets[1]),
      );
      expect(kexInit.kexAlgorithms, contains('kex-strict-s-v00@openssh.com'));
      expect(
        kexInit.kexAlgorithms,
        isNot(contains('kex-strict-c-v00@openssh.com')),
      );

      transport.close();
    });

    test('rekey KEXINIT does not advertise the strict flag', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      // Simulate a completed initial key exchange.
      setPrivate(transport, '_sessionId',
          Uint8List.fromList(List<int>.filled(32, 1)));
      setPrivate(transport, '_kexInProgress', false);
      setPrivate(transport, '_sentKexInit', false);

      transport.rekey();

      final kexInit = SSH_Message_KexInit.decode(
        packetPayload(socket.packets.last),
      );
      expect(
        kexInit.kexAlgorithms,
        isNot(contains('kex-strict-c-v00@openssh.com')),
      );

      transport.close();
    });

    test('enables strict mode when server advertises kex-strict-s', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_kexInProgress', true);
      setPrivate(transport, '_sentKexInit', true);

      final payload = buildKexInit(kexAlgorithms: [
        SSHKexType.x25519.name,
        'kex-strict-s-v00@openssh.com',
      ]).encode();

      reflect(transport)
          .invoke(privateSymbol('_handleMessageKexInit'), [payload]);

      expect(getPrivate<bool>(transport, '_strictKex'), isTrue);

      transport.close();
    });

    test('does not enable strict mode from the client-side flag', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_kexInProgress', true);
      setPrivate(transport, '_sentKexInit', true);

      final payload = buildKexInit(kexAlgorithms: [
        SSHKexType.x25519.name,
        'kex-strict-c-v00@openssh.com',
      ]).encode();

      reflect(transport)
          .invoke(privateSymbol('_handleMessageKexInit'), [payload]);

      expect(getPrivate<bool>(transport, '_strictKex'), isFalse);

      transport.close();
    });

    test('ignores strict flag advertised during rekey', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      // Rekey: session id already established.
      setPrivate(transport, '_sessionId',
          Uint8List.fromList(List<int>.filled(32, 1)));
      setPrivate(transport, '_kexInProgress', true);
      setPrivate(transport, '_sentKexInit', true);

      final payload = buildKexInit(kexAlgorithms: [
        SSHKexType.x25519.name,
        'kex-strict-s-v00@openssh.com',
      ]).encode();

      reflect(transport)
          .invoke(privateSymbol('_handleMessageKexInit'), [payload]);

      expect(getPrivate<bool>(transport, '_strictKex'), isFalse);

      transport.close();
    });

    test('terminates when strict KEXINIT is not the first packet', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_kexInProgress', true);
      setPrivate(transport, '_sentKexInit', true);
      // Some packet was already received before KEXINIT.
      setSequenceValue(transport, '_remotePacketSN', 3);

      final payload = buildKexInit(kexAlgorithms: [
        SSHKexType.x25519.name,
        'kex-strict-s-v00@openssh.com',
      ]).encode();

      expect(
        () => reflect(transport)
            .invoke(privateSymbol('_handleMessageKexInit'), [payload]),
        throwsA(isA<SSHPacketError>()),
      );

      transport.close();
    });

    test('terminates on SSH_MSG_IGNORE during strict initial kex', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_strictKex', true);

      // SSH_MSG_IGNORE with empty data.
      final ignorePayload = Uint8List.fromList([2, 0, 0, 0, 0]);

      expect(
        () => reflect(transport)
            .invoke(privateSymbol('_handleMessage'), [ignorePayload]),
        throwsA(isA<SSHPacketError>()),
      );

      transport.close();
    });

    test('terminates on SSH_MSG_DEBUG during strict initial kex', () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_strictKex', true);

      // SSH_MSG_DEBUG: always_display=false, empty message, empty language.
      final debugPayload = Uint8List.fromList([4, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

      expect(
        () => reflect(transport)
            .invoke(privateSymbol('_handleMessage'), [debugPayload]),
        throwsA(isA<SSHPacketError>()),
      );

      transport.close();
    });

    test('allows SSH_MSG_IGNORE after strict initial kex completes', () {
      final socket = _CaptureSSHSocket();
      Uint8List? received;
      final transport = SSHTransport(
        socket,
        onPacket: (packet) => received = packet,
      );

      setPrivate(transport, '_strictKex', true);
      setPrivate(transport, '_initialKexDone', true);

      final ignorePayload = Uint8List.fromList([2, 0, 0, 0, 0]);
      reflect(transport)
          .invoke(privateSymbol('_handleMessage'), [ignorePayload]);

      expect(received, ignorePayload);

      transport.close();
    });

    test('allows SSH_MSG_IGNORE during kex when strict is not negotiated', () {
      final socket = _CaptureSSHSocket();
      Uint8List? received;
      final transport = SSHTransport(
        socket,
        onPacket: (packet) => received = packet,
      );

      final ignorePayload = Uint8List.fromList([2, 0, 0, 0, 0]);
      reflect(transport)
          .invoke(privateSymbol('_handleMessage'), [ignorePayload]);

      expect(received, ignorePayload);

      transport.close();
    });

    test('resets local sequence number after sending NEWKEYS in strict mode',
        () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_strictKex', true);
      setSequenceValue(transport, '_localPacketSN', 5);

      reflect(transport).invoke(privateSymbol('_sendNewKeys'), const []);

      expect(getSequenceValue(transport, '_localPacketSN'), 0);

      transport.close();
    });

    test('keeps local sequence number after sending NEWKEYS without strict',
        () {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setSequenceValue(transport, '_localPacketSN', 5);

      reflect(transport).invoke(privateSymbol('_sendNewKeys'), const []);

      expect(getSequenceValue(transport, '_localPacketSN'), 6);

      transport.close();
    });

    test('resets remote sequence number after receiving NEWKEYS in strict mode',
        () async {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      // Minimal state so _applyRemoteKeys succeeds (AEAD: no cipher objects).
      setPrivate(transport, '_remoteVersion', 'SSH-2.0-test');
      setPrivate(transport, '_kexType', SSHKexType.x25519);
      setPrivate(transport, '_sharedSecret', BigInt.from(1));
      setPrivate(transport, '_exchangeHash',
          Uint8List.fromList(List<int>.filled(32, 1)));
      setPrivate(transport, '_sessionId',
          Uint8List.fromList(List<int>.filled(32, 2)));
      setPrivate(transport, '_serverCipherType', SSHCipherType.aes128gcm);
      setPrivate(transport, '_strictKex', true);
      setSequenceValue(transport, '_remotePacketSN', 7);

      // SSH_MSG_NEWKEYS as a cleartext packet.
      socket.addIncomingBytes(
        SSHPacket.pack(Uint8List.fromList([21]), align: SSHPacket.minAlign),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(getSequenceValue(transport, '_remotePacketSN'), 0);
      expect(getPrivate<bool>(transport, '_initialKexDone'), isTrue);

      transport.close();
    });

    test('increments remote sequence number after NEWKEYS without strict',
        () async {
      final socket = _CaptureSSHSocket();
      final transport = SSHTransport(socket);

      setPrivate(transport, '_remoteVersion', 'SSH-2.0-test');
      setPrivate(transport, '_kexType', SSHKexType.x25519);
      setPrivate(transport, '_sharedSecret', BigInt.from(1));
      setPrivate(transport, '_exchangeHash',
          Uint8List.fromList(List<int>.filled(32, 1)));
      setPrivate(transport, '_sessionId',
          Uint8List.fromList(List<int>.filled(32, 2)));
      setPrivate(transport, '_serverCipherType', SSHCipherType.aes128gcm);
      setSequenceValue(transport, '_remotePacketSN', 7);

      socket.addIncomingBytes(
        SSHPacket.pack(Uint8List.fromList([21]), align: SSHPacket.minAlign),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(getSequenceValue(transport, '_remotePacketSN'), 8);

      transport.close();
    });
  });
}

class _CaptureSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();
  final packets = <Uint8List>[];

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _CaptureSink(packets);

  @override
  Future<void> get done => _doneCompleter.future;

  void addIncomingBytes(Uint8List data) {
    _inputController.add(Uint8List.fromList(data));
  }

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
  }
}

class _CaptureSink implements StreamSink<List<int>> {
  _CaptureSink(this._packets);

  final List<Uint8List> _packets;

  @override
  void add(List<int> data) {
    _packets.add(Uint8List.fromList(data));
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
