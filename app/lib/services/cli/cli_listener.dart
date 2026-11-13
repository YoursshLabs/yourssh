import 'dart:io';

import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_listener_unix.dart';
import 'cli_listener_windows.dart';
import 'cli_server.dart';

/// How long a connected client may take to send its request line (both
/// transports); a slower one is dropped without a reply.
const Duration kCliReadTimeout = Duration(seconds: 5);

/// Accepts CLI connections on the platform's local IPC endpoint and feeds
/// request lines to a [CliServer].
abstract class CliListener {
  /// Creates the run dir (0700) and validates it. Idempotent; [start] calls
  /// it too.
  Future<void> prepare();

  Future<void> start();
  Future<void> stop();
}

/// Another running instance already answers on the endpoint.
class CliEndpointInUse implements Exception {
  const CliEndpointInUse(this.address);
  final String address;
  @override
  String toString() => 'CliEndpointInUse: $address';
}

/// Creates (and on macOS/Linux checks and restricts) the run dir. Runs in
/// main() before the single-instance lock is taken; the listeners call it
/// again from [CliListener.prepare].
Future<void> prepareCliRunDir(CliEndpoint ep) async {
  if (Platform.isWindows) {
    // %LOCALAPPDATA% is per user; no mode bits to set on Windows.
    await Directory(ep.runDir).create(recursive: true);
    return;
  }
  await prepareUnixRunDir(ep);
}

/// Unix socket on macOS/Linux, named pipe on Windows.
CliListener createCliListener(CliEndpoint ep, CliServer server) =>
    Platform.isWindows
        ? WindowsPipeCliListener(ep, server)
        : UnixCliListener(ep, server);
