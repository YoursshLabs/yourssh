import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_handlers.dart';
import 'cli_listener.dart';
import 'cli_server.dart';
import 'peer_cred.dart';

/// The CLI endpoint for this machine, or null where it is not supported yet
/// (Windows named pipes arrive in a later task).
CliEndpoint? resolveCliEndpoint() {
  if (Platform.isWindows) return null;
  return CliEndpoint.resolve(
    os: Platform.isMacOS ? 'macos' : 'linux',
    env: Platform.environment,
    home: Platform.environment['HOME'] ?? '',
    uid: currentUid(),
  );
}

/// Maps a second launch's argv to a request: a `yourssh://` URL opens that
/// host; anything else just raises the running window.
({String cmd, Map<String, Object?> args}) requestForArgs(List<String> args) {
  for (final a in args) {
    if (a.startsWith('yourssh://')) {
      return (cmd: 'open', args: {'url': a});
    }
  }
  return (cmd: 'activate', args: const <String, Object?>{});
}

/// Hands this launch's request to an already-running instance. True when one
/// answered `ok` (the caller should then exit 0); false when none is alive.
/// Never throws.
Future<bool> forwardToRunningInstance(List<String> args, CliEndpoint ep,
    {Duration deadline = const Duration(seconds: 3)}) async {
  if (Platform.isWindows) return false;
  final req = requestForArgs(args);
  final end = DateTime.now().add(deadline);
  // A winner that just bound its socket may not have rewritten the token
  // yet; retry denials briefly. "Nobody listening" returns at once.
  while (true) {
    final r = await _tryOnce(req, ep);
    if (r == _Attempt.ok) return true;
    if (r == _Attempt.noInstance) return false;
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

enum _Attempt { ok, noInstance, retry }

Future<_Attempt> _tryOnce(
    ({String cmd, Map<String, Object?> args}) req, CliEndpoint ep) async {
  Socket socket;
  try {
    socket = await Socket.connect(
            InternetAddress(ep.address, type: InternetAddressType.unix), 0)
        .timeout(const Duration(seconds: 1));
  } on SocketException {
    return _Attempt.noInstance;
  } on TimeoutException {
    return _Attempt.noInstance;
  }
  try {
    final token = await readToken(ep.tokenPath);
    if (token == null) return _Attempt.retry;
    socket.write(CliRequest(
            id: 'fwd', token: token, cmd: req.cmd, args: req.args)
        .encode());
    socket.write('\n');
    await socket.flush();
    final line = await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 5));
    final resp = CliResponse.decode(line.trim());
    if (resp.ok) return _Attempt.ok;
    return resp.code == CliExit.denied ? _Attempt.retry : _Attempt.noInstance;
  } catch (e) {
    debugPrint('single_instance: forward failed: $e');
    return _Attempt.noInstance;
  } finally {
    socket.destroy();
  }
}

/// Binds the endpoint and publishes the token. Returns the running listener,
/// or null when another instance already owns the endpoint — in that case
/// [args] were forwarded to it and the caller should exit.
///
/// The socket is bound BEFORE the token file is rewritten, so an instance
/// that loses a start race never overwrites the winner's token.
Future<CliListener?> startCliEndpoint(
    CliEndpoint ep, CliHandlers handlers, List<String> args) async {
  final token = generateToken();
  final listener = createCliListener(
      ep, CliServer(handlers: handlers, token: token));
  try {
    await listener.start();
  } on CliEndpointInUse {
    if (await forwardToRunningInstance(args, ep)) return null;
    // Something holds the socket but never answered: leave it alone.
    rethrow;
  }
  try {
    await writeToken(ep.runDir, token: token);
    await File('${ep.runDir}/app.path')
        .writeAsString(Platform.resolvedExecutable, flush: true);
  } catch (_) {
    await listener.stop();
    rethrow;
  }
  return listener;
}
