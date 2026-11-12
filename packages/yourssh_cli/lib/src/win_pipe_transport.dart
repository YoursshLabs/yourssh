import 'dart:convert';
import 'dart:isolate';

import '../client.dart';
import '../endpoint.dart';
import '../protocol.dart';
import 'win_pipe.dart';

/// Exit-4 message when the pipe cannot be opened although it exists.
const String kPipeCannotOpen =
    'cannot open the YourSSH pipe (access denied or busy)';

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
    this.peerCheck = pipeServerIsCurrentUser,
  });

  /// Write + read deadline once the pipe is open.
  final Duration timeout;
  final int maxResponseBytes;

  /// How long to wait for a free instance when the pipe exists but cannot
  /// be opened (WaitNamedPipeW).
  final Duration busyWait;

  /// R22: the server process must run as our user. A seam for tests; must be
  /// a top-level function (it is sent to the I/O isolate).
  final bool Function(int pipe) peerCheck;

  /// True when something serves the pipe. Throws [CliPermissionDenied] when
  /// the server runs as another user.
  @override
  Future<bool> probe(CliEndpoint ep) async {
    int? pipe;
    try {
      pipe = tryOpenPipeClient(ep.address);
    } on Object {
      return false; // not on Windows
    }
    if (pipe == null) return pipeExists(ep.address); // busy or denied
    try {
      if (!peerCheck(pipe)) throw CliPermissionDenied(kPipeOwnedByAnotherUser);
      return true;
    } finally {
      closeWinHandle(pipe);
    }
  }

  @override
  Future<String> roundTrip(CliEndpoint ep, String requestLine) =>
      _roundTripInIsolate(ep.address, requestLine, timeout.inMilliseconds,
          maxResponseBytes, busyWait.inMilliseconds, peerCheck);
}

// Top-level so the closure captures only these sendable values.
Future<String> _roundTripInIsolate(
        String address,
        String requestLine,
        int timeoutMs,
        int maxResponseBytes,
        int busyWaitMs,
        bool Function(int pipe) peerCheck) =>
    Isolate.run(
        () => pipeRoundTrip(address, requestLine,
            timeoutMs: timeoutMs,
            maxResponseBytes: maxResponseBytes,
            busyWaitMs: busyWaitMs,
            peerCheck: peerCheck),
        debugName: 'yourssh-pipe');

/// Blocking request/response over pipe [address]: open, check the server
/// with [peerCheck], run [beforeSend] (grant the verified server foreground
/// rights), write the line, read one line back.
String pipeRoundTrip(String address, String requestLine,
    {required int timeoutMs,
    required int maxResponseBytes,
    required int busyWaitMs,
    bool Function(int pipe) peerCheck = pipeServerIsCurrentUser,
    void Function(int pipe) beforeSend = _allowForeground}) {
  final pipe = openPipeForClient(address, busyWaitMs: busyWaitMs);
  try {
    // R22: the pipe namespace is global and another user could have taken
    // the name first. Check the server before the token leaves this process.
    if (!peerCheck(pipe)) throw CliPermissionDenied(kPipeOwnedByAnotherUser);
    // The app raises its window for most requests; Windows only lets it
    // take the foreground if we pass on our right to do so.
    beforeSend(pipe);
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

void _allowForeground(int pipe) => allowPipeServerForeground(pipe);

/// Open phase (R25: decided by listing `\\.\pipe\`, not by the last error):
/// - opens → the handle;
/// - not listed → [CliUnreachable] (launch and retry);
/// - listed → WaitNamedPipeW up to [busyWaitMs], one more try; still
///   failing → [CliPermissionDenied] (exit 4), unless the name vanished
///   meanwhile (→ unreachable).
int openPipeForClient(String address, {required int busyWaitMs}) {
  final first = tryOpenPipeClient(address);
  if (first != null) return first;
  if (!pipeExists(address)) throw CliUnreachable('pipe not found');
  waitPipeAvailable(address, timeoutMs: busyWaitMs);
  final second = tryOpenPipeClient(address);
  if (second != null) return second;
  if (!pipeExists(address)) throw CliUnreachable('pipe not found');
  throw CliPermissionDenied(kPipeCannotOpen);
}
