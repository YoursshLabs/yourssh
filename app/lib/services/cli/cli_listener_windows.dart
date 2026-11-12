import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yourssh_cli/win_pipe.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

import 'cli_listener.dart';
import 'cli_server.dart';

/// Upper bound for writing one response (a large `ls`) to a client.
const Duration kCliWriteTimeout = Duration(seconds: 30);

/// How long [WindowsPipeCliListener.stop] waits for its isolates.
const Duration _stopGrace = Duration(seconds: 2);

/// Windows named pipe `\\.\pipe\yourssh-cli-<SID>`: protected DACL for the
/// current user only, remote clients rejected, byte mode, overlapped I/O.
///
/// One accept isolate waits for clients (it always keeps a listening
/// instance) and hands each connected handle to this isolate. Every client
/// then gets short-lived worker isolates: one reads the request line (peer
/// SID check, [readTimeout], 64 KiB cap), this isolate runs [CliServer], one
/// writes the response. A slow client therefore never blocks another. All
/// blocking waits also wait on one stop event, which [stop] signals.
class WindowsPipeCliListener implements CliListener {
  WindowsPipeCliListener(
    this._ep,
    this._server, {
    this.readTimeout = kCliReadTimeout,
    this.writeTimeout = kCliWriteTimeout,
  });

  final CliEndpoint _ep;
  final CliServer _server;
  final Duration readTimeout;
  final Duration writeTimeout;

  int _stopEvent = 0;
  bool _stopping = false;
  bool _acceptExited = false;
  Isolate? _accept;
  ReceivePort? _messages;
  Completer<void>? _acceptDone;
  final Set<_PipeConn> _conns = {};

  @override
  Future<void> prepare() async {
    // %LOCALAPPDATA% is per user; no mode bits to set on Windows.
    await Directory(_ep.runDir).create(recursive: true);
  }

  @override
  Future<void> start() async {
    if (_stopEvent != 0 || _stopping) {
      throw StateError('WindowsPipeCliListener can only start once');
    }
    await prepare();
    final sid = currentUserSid();
    int first;
    try {
      first = createPipeServerInstance(_ep.address, sid: sid, first: true);
    } on WinPipeException {
      // FILE_FLAG_FIRST_PIPE_INSTANCE fails when the name exists (another
      // instance, or another user's pipe squatting it). R25: decided by
      // listing \\.\pipe\, never by the last error.
      if (pipeExists(_ep.address)) throw CliEndpointInUse(_ep.address);
      rethrow;
    }
    int stop;
    try {
      stop = createStopEvent();
    } catch (_) {
      closeWinHandle(first);
      rethrow;
    }
    final messages = ReceivePort('cli-pipe-accept');
    final done = Completer<void>();
    // Set before spawning: a client may be handed over before spawn returns.
    _messages = messages;
    _acceptDone = done;
    _stopEvent = stop;
    messages.listen((m) => _onMessage(m, done));
    try {
      _accept = await Isolate.spawn(
        _acceptLoop,
        (
          address: _ep.address,
          sid: sid,
          first: first,
          stop: stop,
          out: messages.sendPort,
        ),
        onExit: messages.sendPort,
        onError: messages.sendPort,
        debugName: 'cli-pipe-accept',
      );
    } catch (_) {
      messages.close();
      _messages = null;
      _acceptDone = null;
      _stopEvent = 0;
      closeWinHandle(first);
      closeWinHandle(stop);
      rethrow;
    }
  }

  void _onMessage(Object? m, Completer<void> done) {
    if (m is int) {
      _onClient(m);
    } else if (m == null) {
      // onExit: arrives after every message the isolate sent on this port.
      _acceptExited = true;
      if (!done.isCompleted) done.complete();
    } else {
      debugPrint('CliListener: $m');
    }
  }

  void _onClient(int pipe) {
    if (_stopping) {
      closeWinHandle(pipe);
      return;
    }
    final c = _PipeConn(pipe);
    _conns.add(c);
    unawaited(_serve(c));
  }

  Future<void> _serve(_PipeConn c) async {
    final stop = _stopEvent;
    try {
      c.inWorker = true;
      final line =
          await _readRequest(c.pipe, stop, readTimeout.inMilliseconds);
      c.inWorker = false;
      // Null: foreign SID, timeout, too long, bad UTF-8 or closed — drop
      // without a reply, like the Unix listener.
      if (line == null || c.closed || _stopping) return;
      final out = await _server.handleLine(line, trusted: false);
      if (c.closed || _stopping) return;
      c.inWorker = true;
      await _writeResponse(c.pipe, stop, utf8.encode('$out\n'),
          writeTimeout.inMilliseconds);
    } catch (e) {
      debugPrint('CliListener: respond failed: $e');
    } finally {
      c.inWorker = false;
      _close(c);
      c.done.complete();
    }
  }

  void _close(_PipeConn c) {
    _conns.remove(c);
    if (c.closed) return;
    c.closed = true;
    closeWinHandle(c.pipe);
  }

  @override
  Future<void> stop() async {
    final stopEvent = _stopEvent;
    // Never started (e.g. start() threw CliEndpointInUse): nothing here is
    // ours, and the live instance must not be touched.
    if (stopEvent == 0 || _stopping) return;
    _stopping = true;
    signalEvent(stopEvent);

    // The accept isolate cancels its pending ConnectNamedPipe and closes
    // the listening instance.
    await _acceptDone!.future.timeout(_stopGrace, onTimeout: () {
      debugPrint('CliListener: accept isolate did not stop in time');
      _accept?.kill(priority: Isolate.immediate);
    });
    _messages?.close();

    // Clients waiting on the app (CliServer) are closed now; workers see the
    // stop event, cancel their I/O and are closed when they return.
    final working = <Future<void>>[];
    for (final c in _conns.toList()) {
      if (c.inWorker) {
        working.add(c.done.future);
      } else {
        _close(c);
      }
    }
    var drained = true;
    await Future.wait(working).timeout(_stopGrace, onTimeout: () {
      drained = false;
      debugPrint('CliListener: pipe workers did not stop in time');
      return const <void>[];
    });
    // A worker still waiting on the event must not see its handle reused.
    if (drained && _acceptExited) closeWinHandle(stopEvent);
    _stopEvent = 0;
  }
}

class _PipeConn {
  _PipeConn(this.pipe);
  final int pipe;
  bool closed = false;

  /// A worker isolate is using [pipe]; only it may close it.
  bool inWorker = false;
  final Completer<void> done = Completer<void>();
}

// The isolate bodies below are top-level so their closures capture only the
// sendable values passed in.

Future<String?> _readRequest(int pipe, int stop, int timeoutMs) => Isolate.run(
      () => serveReadRequest(pipe,
          stopEvent: stop, timeoutMs: timeoutMs, maxBytes: kMaxRequestBytes),
      debugName: 'cli-pipe-read',
    );

Future<void> _writeResponse(
        int pipe, int stop, Uint8List bytes, int timeoutMs) =>
    Isolate.run(
      () => serveWriteResponse(pipe, bytes,
          stopEvent: stop, timeoutMs: timeoutMs),
      debugName: 'cli-pipe-write',
    );

/// Accept loop: wait for a client on the listening instance, create the
/// next instance, then hand the connected one to the main isolate. Ends when
/// the stop event is signalled.
///
/// The next instance is created before the current one is handed off or
/// closed, so the pipe name never lapses while the listener runs (a lapse
/// would let another user's process take the name).
void _acceptLoop(
    ({String address, String sid, int first, int stop, SendPort out}) a) {
  int next() {
    try {
      return createPipeServerInstance(a.address, sid: a.sid, first: false);
    } on WinPipeException catch (e) {
      a.out.send('cannot create a pipe instance: $e');
      return 0;
    }
  }

  var pipe = a.first;
  while (true) {
    if (waitForEvent(a.stop, timeoutMs: 0)) {
      closeWinHandle(pipe);
      return;
    }
    if (pipe == 0) {
      pipe = next();
      if (pipe == 0) {
        if (waitForEvent(a.stop, timeoutMs: 1000)) return;
        continue;
      }
    }
    PipeConnect r;
    try {
      r = waitForPipeClient(pipe, stopEvent: a.stop);
    } on WinPipeException catch (e) {
      a.out.send('accept failed: $e');
      final replacement = next();
      closeWinHandle(pipe);
      pipe = replacement;
      if (waitForEvent(a.stop, timeoutMs: 100)) {
        closeWinHandle(pipe);
        return;
      }
      continue;
    }
    switch (r) {
      case PipeConnect.stopped:
        closeWinHandle(pipe);
        return;
      case PipeConnect.clientGone:
        disconnectPipe(pipe); // reuse this instance
      case PipeConnect.connected:
        final listening = next();
        a.out.send(pipe);
        pipe = listening;
    }
  }
}
