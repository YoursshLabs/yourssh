import 'dart:async';
import 'dart:io';

/// Generic byte-pipe endpoint so the proxy can be tested without dartssh2:
/// for real tunnels, stream/sink come from an SSHSocket (forwardLocal),
/// whose sink is a `StreamSink<List<int>>` (NOT an IOSink).
class TunnelEnd {
  TunnelEnd({required this.stream, required this.sink, required this.close});
  final Stream<List<int>> stream;
  final StreamSink<List<int>> sink;
  final void Function() close;
}

/// One-shot loopback proxy: binds 127.0.0.1 on a random port, accepts exactly
/// one connection, pipes it to a freshly opened tunnel end, then refuses
/// further connections. Dies with the session ([stop]).
class RdpTunnelProxy {
  RdpTunnelProxy({this.onClosed});

  /// Fired when the tunnel side ends before [stop] — lets the session report
  /// "SSH tunnel closed" instead of a generic disconnect.
  final void Function()? onClosed;

  ServerSocket? _server;
  Socket? _client;
  TunnelEnd? _tunnel;
  bool _stopped = false;

  Future<int> start(Future<TunnelEnd> Function() openTunnel) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((client) async {
      if (_client != null) {
        client.destroy(); // one-shot: refuse extra connections
        return;
      }
      _client = client;
      // A peer reset also rejects the socket's `done` future; without a
      // handler that surfaces as an unhandled zone error on top of the
      // onError callback below (which is the one that actually acts on it).
      unawaited(client.done.then<void>((_) {}, onError: (_) {}));
      try {
        final tunnel = await openTunnel();
        _tunnel = tunnel;
        unawaited(tunnel.sink.done.then<void>((_) {}, onError: (_) {}));
        // Either side ending tears down BOTH sockets — a half-open pipe
        // would otherwise leak the surviving socket and never fire onClosed.
        // Writes are guarded: a buffered chunk can still arrive after the
        // peer reset, and add() on a destroyed socket throws synchronously.
        client.listen((data) {
          if (_ended) return;
          try {
            tunnel.sink.add(data);
          } catch (_) {
            _pipeEnded(client, tunnel);
          }
        },
            onDone: () => _pipeEnded(client, tunnel),
            onError: (_) => _pipeEnded(client, tunnel));
        tunnel.stream.listen((data) {
          if (_ended) return;
          try {
            client.add(data);
          } catch (_) {
            _pipeEnded(client, tunnel);
          }
        },
            onDone: () => _pipeEnded(client, tunnel),
            onError: (_) => _pipeEnded(client, tunnel));
      } catch (_) {
        client.destroy();
        _notifyClosed();
      }
    });
    return server.port;
  }

  bool _ended = false;

  void _pipeEnded(Socket client, TunnelEnd tunnel) {
    if (_ended) return; // both directions report; tear down once
    _ended = true;
    client.destroy();
    tunnel.close();
    _notifyClosed();
  }

  void _notifyClosed() {
    if (!_stopped) onClosed?.call();
  }

  Future<void> stop() async {
    _stopped = true;
    await _server?.close();
    _client?.destroy();
    _tunnel?.close();
  }
}
