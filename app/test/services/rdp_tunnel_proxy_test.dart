import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/rdp_tunnel_proxy.dart';

void main() {
  test('pipes bytes both ways through one accepted connection', () async {
    // Fake "remote" echo server stands in for the SSH-forwarded end.
    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((s) => s.listen(s.add));

    final proxy = RdpTunnelProxy();
    final port = await proxy.start(() async {
      final socket = await Socket.connect('127.0.0.1', echo.port);
      return TunnelEnd(stream: socket, sink: socket, close: socket.destroy);
    });

    final client = await Socket.connect('127.0.0.1', port);
    client.add([1, 2, 3]);
    final received = await client.first;
    expect(received, [1, 2, 3]);

    client.destroy();
    await proxy.stop();
    await echo.close();
  });

  test('tunnel side ending fires onClosed and tears down the client',
      () async {
    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? remoteSide;
    echo.listen((s) => remoteSide = s);

    final closed = Completer<void>();
    final proxy = RdpTunnelProxy(onClosed: () {
      if (!closed.isCompleted) closed.complete();
    });
    final port = await proxy.start(() async {
      final socket = await Socket.connect('127.0.0.1', echo.port);
      return TunnelEnd(stream: socket, sink: socket, close: socket.destroy);
    });

    final client = await Socket.connect('127.0.0.1', port);
    client.add([1]); // ensure the pipe is established
    await Future<void>.delayed(const Duration(milliseconds: 50));

    remoteSide!.destroy(); // SSH side collapses
    await closed.future.timeout(const Duration(seconds: 5));

    await proxy.stop();
    await echo.close();
  });

  test('client side ending also fires onClosed (symmetric teardown)',
      () async {
    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((s) => s.listen(s.add));

    final closed = Completer<void>();
    final proxy = RdpTunnelProxy(onClosed: () {
      if (!closed.isCompleted) closed.complete();
    });
    final port = await proxy.start(() async {
      final socket = await Socket.connect('127.0.0.1', echo.port);
      return TunnelEnd(stream: socket, sink: socket, close: socket.destroy);
    });

    final client = await Socket.connect('127.0.0.1', port);
    client.add([1]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    client.destroy(); // RDP engine side drops first
    await closed.future.timeout(const Duration(seconds: 5));

    await proxy.stop();
    await echo.close();
  });

  test('onClosed does not fire on explicit stop()', () async {
    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((s) => s.listen(s.add));

    var fired = false;
    final proxy = RdpTunnelProxy(onClosed: () => fired = true);
    final port = await proxy.start(() async {
      final socket = await Socket.connect('127.0.0.1', echo.port);
      return TunnelEnd(stream: socket, sink: socket, close: socket.destroy);
    });

    final client = await Socket.connect('127.0.0.1', port);
    client.add([1]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await proxy.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fired, isFalse);

    client.destroy();
    await echo.close();
  });
}
