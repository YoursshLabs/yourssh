import 'dart:convert';
import 'dart:io' show sleep;
import 'dart:isolate';

import '../client.dart';
import '../endpoint.dart';
import '../protocol.dart';
import 'win_pipe.dart';

/// Windows named-pipe transport. Same contract as [UnixSocketTransport]:
/// only open-phase failures are [CliUnreachable] (and may be retried with a
/// launch); after the pipe is open every failure is a runtime error (R20).
///
/// The blocking pipe I/O runs in a short-lived isolate, so the caller's
/// isolate (the app's UI isolate when forwarding a second launch) never
/// blocks.
class WindowsPipeTransport implements CliTransport {
  WindowsPipeTransport({
    this.timeout = const Duration(seconds: 30),
    this.maxResponseBytes = kMaxResponseBytes,
    this.busyWait = const Duration(seconds: 2),
  });

  /// Write + read deadline once the pipe is open.
  final Duration timeout;
  final int maxResponseBytes;

  /// How long to wait for a free instance (ERROR_PIPE_BUSY).
  final Duration busyWait;

  @override
  Future<bool> probe(CliEndpoint ep) async {
    try {
      closeWinHandle(openPipeClient(ep.address));
      return true;
    } on WinPipeException catch (e) {
      return e.code == WinError.pipeBusy; // exists, every instance in use
    } on Object {
      return false;
    }
  }

  @override
  Future<String> roundTrip(CliEndpoint ep, String requestLine) =>
      _roundTripInIsolate(ep.address, requestLine, timeout.inMilliseconds,
          maxResponseBytes, busyWait.inMilliseconds);
}

// Top-level so the closure captures only these sendable values.
Future<String> _roundTripInIsolate(String address, String requestLine,
        int timeoutMs, int maxResponseBytes, int busyWaitMs) =>
    Isolate.run(
        () => pipeRoundTrip(address, requestLine,
            timeoutMs: timeoutMs,
            maxResponseBytes: maxResponseBytes,
            busyWaitMs: busyWaitMs),
        debugName: 'yourssh-pipe');

/// Blocking request/response over pipe [address]: open, check that the
/// server runs as our user, write the line, read one line back.
String pipeRoundTrip(String address, String requestLine,
    {required int timeoutMs,
    required int maxResponseBytes,
    required int busyWaitMs}) {
  final pipe = _open(address, busyWaitMs);
  try {
    // R22: the pipe namespace is global and another user could have taken
    // the name first. Check the server before the token leaves this process.
    if (!pipeServerIsCurrentUser(pipe)) {
      throw CliPermissionDenied(kPipeOwnedByAnotherUser);
    }
    final sw = Stopwatch()..start();
    switch (writePipeAll(pipe, utf8.encode('$requestLine\n'),
        timeoutMs: timeoutMs)) {
      case PipeIoEnd.done:
        break;
      case PipeIoEnd.timeout:
        throw CliTimeout(timeoutMs ~/ 1000);
      default:
        throw CliConnectionLost();
    }
    final r = readPipeLine(pipe,
        timeoutMs: timeoutMs - sw.elapsedMilliseconds,
        maxBytes: maxResponseBytes);
    switch (r.end) {
      case PipeIoEnd.newline:
        return utf8.decode(r.bytes, allowMalformed: true);
      case PipeIoEnd.closed:
        if (r.bytes.isEmpty) throw CliConnectionLost();
        return utf8.decode(r.bytes, allowMalformed: true);
      case PipeIoEnd.tooLong:
        throw CliProtocolException(CliExit.usage, 'response too long');
      case PipeIoEnd.timeout:
        throw CliTimeout(timeoutMs ~/ 1000);
      default:
        throw CliConnectionLost();
    }
  } finally {
    closeWinHandle(pipe);
  }
}

/// Open phase: missing pipe → unreachable, access denied → denied, all
/// instances busy → wait up to [busyWaitMs], then a 2 s-style timeout.
int _open(String address, int busyWaitMs) {
  final sw = Stopwatch()..start();
  while (true) {
    try {
      return openPipeClient(address);
    } on WinPipeException catch (e) {
      switch (e.code) {
        case WinError.fileNotFound:
          throw CliUnreachable('pipe not found');
        case WinError.accessDenied:
          throw CliPermissionDenied('permission denied on the YourSSH pipe');
        case WinError.pipeBusy:
          final left = busyWaitMs - sw.elapsedMilliseconds;
          if (left <= 0) throw CliTimeout(busyWaitMs ~/ 1000);
          if (!waitPipeAvailable(address, timeoutMs: left)) {
            sleep(const Duration(milliseconds: 10));
          }
        default:
          rethrow;
      }
    }
  }
}
