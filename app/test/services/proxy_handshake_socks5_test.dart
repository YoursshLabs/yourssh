import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/proxy_handshake.dart';

class _ListSink implements StreamSink<List<int>> {
  final List<int> bytes = [];
  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  void addError(Object error, [StackTrace? st]) {}
  @override
  Future addStream(Stream<List<int>> stream) => stream.forEach(add);
  @override
  Future close() async {}
  @override
  Future get done => Future.value();
}

void main() {
  test('no-auth path: greeting, CONNECT with domain ATYP, success', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = socks5Handshake(reader, sink,
        targetHost: 'host.internal', targetPort: 2222);

    // greeting: VER=5, NMETHODS=1, METHOD=0x00
    expect(sink.bytes.sublist(0, 3), [0x05, 0x01, 0x00]);
    input.add(Uint8List.fromList([0x05, 0x00])); // select no-auth

    await Future<void>.delayed(Duration.zero); // let CONNECT be written
    final host = 'host.internal'.codeUnits;
    final expected = [0x05, 0x01, 0x00, 0x03, host.length, ...host, 0x08, 0xAE];
    expect(sink.bytes.sublist(3), expected);

    // reply: VER, REP=0, RSV, ATYP=1 (ipv4), 4 addr, 2 port, then 'SS' leftover
    input.add(Uint8List.fromList(
        [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0x53, 0x53]));
    final leftover = await future;
    expect(leftover, [0x53, 0x53]);
  });

  test('user/pass path: RFC 1929 auth then success', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = socks5Handshake(reader, sink,
        targetHost: 'h', targetPort: 22, username: 'u', password: 'p');

    expect(sink.bytes.sublist(0, 4), [0x05, 0x02, 0x00, 0x02]);
    input.add(Uint8List.fromList([0x05, 0x02])); // select user/pass

    await Future<void>.delayed(Duration.zero);
    const authStart = 4;
    expect(sink.bytes.sublist(authStart, authStart + 5),
        [0x01, 0x01, 0x75 /* u */, 0x01, 0x70 /* p */]);
    input.add(Uint8List.fromList([0x01, 0x00])); // auth success

    await Future<void>.delayed(Duration.zero);
    input.add(Uint8List.fromList([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
    await future; // completes without throwing
  });

  test('reply 0x05 maps to connection refused', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = socks5Handshake(reader, sink, targetHost: 'h', targetPort: 22);
    input.add(Uint8List.fromList([0x05, 0x00]));
    await Future<void>.delayed(Duration.zero);
    input.add(Uint8List.fromList([0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0]));
    await expectLater(
        future,
        throwsA(isA<ProxyException>().having(
            (e) => e.message, 'message', contains('refused'))));
  });

  test('auth failure throws', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = socks5Handshake(reader, sink,
        targetHost: 'h', targetPort: 22, username: 'u', password: 'bad');
    input.add(Uint8List.fromList([0x05, 0x02]));
    await Future<void>.delayed(Duration.zero);
    input.add(Uint8List.fromList([0x01, 0x01])); // auth fail
    await expectLater(future, throwsA(isA<ProxyException>()));
  });

  for (final long in ['user', 'pass']) {
    test('SOCKS5 $long longer than 255 bytes is rejected, nothing sent',
        () async {
      final input = StreamController<Uint8List>();
      final sink = _ListSink();
      final reader = ByteReader(input.stream);
      final big = 'a' * 256;
      await expectLater(
          socks5Handshake(reader, sink,
              targetHost: 'h',
              targetPort: 22,
              username: long == 'user' ? big : 'u',
              password: long == 'pass' ? big : 'p'),
          throwsA(isA<ProxyException>()));
      expect(sink.bytes, isEmpty);
    });
  }
}
