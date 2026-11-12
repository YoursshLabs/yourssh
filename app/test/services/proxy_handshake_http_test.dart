import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/proxy_handshake.dart';

/// Minimal StreamSink that records everything written.
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
  test('200 success returns leftover bytes', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = httpConnectHandshake(reader, sink,
        targetHost: 'example.com', targetPort: 22);

    expect(utf8.decode(sink.bytes), contains('CONNECT example.com:22 HTTP/1.1'));
    expect(utf8.decode(sink.bytes), isNot(contains('Proxy-Authorization')));

    input.add(Uint8List.fromList(
        utf8.encode('HTTP/1.1 200 Connection established\r\n\r\nSSHPREFIX')));
    final leftover = await future;
    expect(utf8.decode(leftover), 'SSHPREFIX');
  });

  test('Basic auth header is sent when credentials given', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = httpConnectHandshake(reader, sink,
        targetHost: 'h', targetPort: 22, username: 'u', password: 'p');
    final expected = base64.encode(utf8.encode('u:p'));
    expect(utf8.decode(sink.bytes), contains('Proxy-Authorization: Basic $expected'));
    input.add(Uint8List.fromList(utf8.encode('HTTP/1.1 200 OK\r\n\r\n')));
    await future;
  });

  test('non-200 throws ProxyException', () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    final future = httpConnectHandshake(reader, sink, targetHost: 'h', targetPort: 22);
    input.add(Uint8List.fromList(
        utf8.encode('HTTP/1.1 407 Proxy Authentication Required\r\n\r\n')));
    await expectLater(future, throwsA(isA<ProxyException>()));
  });

  test('response headers larger than 64 KiB fail', () async {
    final input = StreamController<Uint8List>();
    final reader = ByteReader(input.stream);
    final future = httpConnectHandshake(reader, _ListSink(),
        targetHost: 'example.com', targetPort: 22);
    final expectation = expectLater(future, throwsA(isA<ProxyException>()));
    input.add(Uint8List(70 * 1024)..fillRange(0, 70 * 1024, 0x41));
    await expectation;
  });

  test('CR/LF in the target host is rejected before anything is sent',
      () async {
    final input = StreamController<Uint8List>();
    final sink = _ListSink();
    final reader = ByteReader(input.stream);
    await expectLater(
        httpConnectHandshake(reader, sink,
            targetHost: 'a.com\r\nX-Evil: 1', targetPort: 22),
        throwsA(isA<ProxyException>()));
    expect(sink.bytes, isEmpty);
  });
}
