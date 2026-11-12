import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_listener.dart';
import 'cli_server.dart';
import 'peer_cred.dart';

const Duration kCliReadTimeout = Duration(seconds: 5);

class UnixCliListener implements CliListener {
  UnixCliListener(this._ep, this._server);

  final CliEndpoint _ep;
  final CliServer _server;
  ServerSocket? _socket;
  StreamSubscription<Socket>? _sub;
  final _live = <Socket>{};

  InternetAddress get _addr =>
      InternetAddress(_ep.address, type: InternetAddressType.unix);

  @override
  Future<void> start() async {
    final dir = Directory(_ep.runDir);
    await dir.create(recursive: true);
    await _chmod('700', _ep.runDir);

    if (FileSystemEntity.typeSync(_ep.address) !=
        FileSystemEntityType.notFound) {
      if (await _isLive()) throw CliEndpointInUse(_ep.address);
      try {
        File(_ep.address).deleteSync();
      } on FileSystemException {
        // Raced with another instance cleaning up; bind decides.
      }
    }

    try {
      _socket = await ServerSocket.bind(_addr, 0);
    } on SocketException {
      // Two instances starting together: the loser sees the winner's socket.
      if (await _isLive()) throw CliEndpointInUse(_ep.address);
      rethrow;
    }
    await _chmod('600', _ep.address);
    _sub = _socket!.listen(_onConnection, onError: (_) {});
  }

  Future<bool> _isLive() async {
    try {
      final s = await Socket.connect(_addr, 0)
          .timeout(const Duration(seconds: 2));
      s.destroy();
      return true;
    } on SocketException {
      return false; // refused / no such file: nobody is listening
    } on TimeoutException {
      return true; // something is there but not accepting; do not steal it
    }
  }

  void _onConnection(Socket socket) {
    if (peerUidOf(socket) != currentUid()) {
      socket.destroy();
      return;
    }
    _live.add(socket);
    final buf = BytesBuilder(copy: false);
    var handled = false;
    late final Timer timer;
    StreamSubscription<Uint8List>? sub;

    void close() {
      timer.cancel();
      sub?.cancel();
      _live.remove(socket);
      socket.destroy();
    }

    timer = Timer(kCliReadTimeout, close);

    Future<void> respond(String line) async {
      sub?.pause();
      try {
        final out = await _server.handleLine(line, trusted: false);
        socket.add(utf8.encode('$out\n'));
        await socket.flush();
      } catch (e) {
        debugPrint('CliListener: respond failed: $e');
      } finally {
        close();
      }
    }

    sub = socket.listen(
      (chunk) {
        if (handled) return;
        final nl = chunk.indexOf(0x0A);
        final lineBytes = nl >= 0 ? nl : chunk.length;
        if (buf.length + lineBytes > kMaxRequestBytes) {
          handled = true;
          close(); // too large: drop without a response
          return;
        }
        if (nl < 0) {
          buf.add(chunk);
          return;
        }
        buf.add(Uint8List.sublistView(chunk, 0, nl));
        handled = true;
        timer.cancel();
        String line;
        try {
          line = utf8.decode(buf.takeBytes());
        } on FormatException {
          close();
          return;
        }
        respond(line);
      },
      onError: (_) => close(),
      onDone: () {
        if (!handled) close();
      },
      cancelOnError: true,
    );
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _socket?.close();
    _socket = null;
    for (final s in _live.toList()) {
      s.destroy();
    }
    _live.clear();
    try {
      final f = File(_ep.address);
      if (FileSystemEntity.typeSync(_ep.address) !=
          FileSystemEntityType.notFound) {
        f.deleteSync();
      }
    } on FileSystemException {
      // Already gone.
    }
  }
}

Future<void> _chmod(String mode, String path) async {
  final r = await Process.run('chmod', [mode, path]);
  if (r.exitCode != 0) {
    throw FileSystemException('chmod $mode failed: ${r.stderr}', path);
  }
}
