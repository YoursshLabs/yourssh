import 'dart:io';

import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_listener_unix.dart';
import 'cli_server.dart';

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

/// Unix socket on macOS/Linux. Windows named pipes arrive in a later task.
CliListener createCliListener(CliEndpoint ep, CliServer server) {
  if (Platform.isWindows) {
    throw UnsupportedError('CLI listener is not implemented on Windows yet');
  }
  return UnixCliListener(ep, server);
}
