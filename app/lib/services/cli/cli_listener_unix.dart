import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_listener.dart';
import 'cli_server.dart';
import 'peer_cred.dart';

class UnixCliListener implements CliListener {
  UnixCliListener(this._ep, this._server);

  final CliEndpoint _ep;
  final CliServer _server;
  ServerSocket? _socket;
  StreamSubscription<Socket>? _sub;
  final _live = <Socket>{};
  bool _warnedPeerCred = false;

  InternetAddress get _addr =>
      InternetAddress(_ep.address, type: InternetAddressType.unix);

  @override
  Future<void> start() async {
    await prepare();

    final existing =
        FileSystemEntity.typeSync(_ep.address, followLinks: false);
    if (existing != FileSystemEntityType.notFound) {
      if (existing != FileSystemEntityType.unixDomainSock) {
        throw FileSystemException(
            'refusing to replace ${existing.toString()} that is not a socket',
            _ep.address);
      }
      if (await _isLive()) throw CliEndpointInUse(_ep.address);
      try {
        File(_ep.address).deleteSync();
      } on FileSystemException {
        // Raced with another instance cleaning up; bind decides.
      }
    }

    ServerSocket socket;
    try {
      socket = await ServerSocket.bind(_addr, 0);
    } on SocketException {
      // Two instances starting together: the loser sees the winner's socket.
      if (await _isLive()) throw CliEndpointInUse(_ep.address);
      rethrow;
    }
    try {
      await _chmod('600', _ep.address);
    } catch (_) {
      await socket.close();
      rethrow;
    }
    _socket = socket;
    _sub = socket.listen(_onConnection, onError: (_) {});
  }

  @override
  Future<void> prepare() => prepareUnixRunDir(_ep);

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
    final peer = peerUidOf(socket);
    if (peer == null && !_warnedPeerCred) {
      _warnedPeerCred = true;
      debugPrint('CliListener: cannot read peer credentials; rejecting');
    }
    if (peer == null || peer != currentUid()) {
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
    final socket = _socket;
    _socket = null;
    await _sub?.cancel();
    _sub = null;
    for (final s in _live.toList()) {
      s.destroy();
    }
    _live.clear();
    // Never touch the path unless this instance bound it: after a failed
    // start() it belongs to the live instance.
    if (socket == null) return;
    await socket.close();
    try {
      if (FileSystemEntity.typeSync(_ep.address, followLinks: false) ==
          FileSystemEntityType.unixDomainSock) {
        File(_ep.address).deleteSync();
      }
    } on FileSystemException {
      // Already gone.
    }
  }
}

/// Creates the run dir and makes it 0700. A shared-temp location another
/// user could have pre-created is trusted only when it is a real directory
/// that is ours and 0700; anything else throws.
Future<void> prepareUnixRunDir(CliEndpoint ep) async {
  final dir = Directory(ep.runDir);
  final existed = dir.existsSync();
  if (!existed) await dir.create(recursive: true);
  if (ep.inSharedTemp) {
    final type = FileSystemEntity.typeSync(ep.runDir, followLinks: false);
    final owner = await _ownerUid(ep.runDir);
    final mode = FileStat.statSync(ep.runDir).mode & 0xFFF;
    if (type != FileSystemEntityType.directory ||
        owner != currentUid() ||
        mode != 0x1C0 /* 0700 */) {
      if (existed || type != FileSystemEntityType.directory) {
        throw FileSystemException(
            'refusing run dir (must be our own directory, mode 0700)',
            ep.runDir);
      }
    }
  }
  await _chmod('700', ep.runDir);
}

/// True when [dir] is a real directory (not a symlink) owned by us with
/// mode 0700 — the condition for trusting a shared-temp run dir.
Future<bool> isPrivateRunDir(String dir) async {
  if (FileSystemEntity.typeSync(dir, followLinks: false) !=
      FileSystemEntityType.directory) {
    return false;
  }
  return await _ownerUid(dir) == currentUid() &&
      (FileStat.statSync(dir).mode & 0x1FF) == 0x1C0;
}

Future<int?> _ownerUid(String path) async {
  final args = Platform.isMacOS ? ['-f', '%u', path] : ['-c', '%u', path];
  final r = await Process.run('/usr/bin/stat', args);
  return r.exitCode == 0 ? int.tryParse((r.stdout as String).trim()) : null;
}

Future<void> _chmod(String mode, String path) async {
  final r = await Process.run('/bin/chmod', [mode, path]);
  if (r.exitCode != 0) {
    throw FileSystemException('chmod $mode failed: ${r.stderr}', path);
  }
}
