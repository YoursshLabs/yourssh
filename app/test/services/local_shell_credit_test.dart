import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/pty_runner.dart';

/// Models the native reader thread with credit based flow control: it keeps
/// posting chunks until [limit] bytes are in flight and resumes when Dart
/// returns credit through [ackBytes].
class _CreditPty implements PtyRunner, CreditPty {
  _CreditPty(this.data, this.limit, {int seed = 1}) : _rng = Random(seed);

  final Uint8List data;
  final int limit;
  final Random _rng;
  final _out = StreamController<List<int>>();
  final _exit = Completer<int>();
  final List<Uint8List> written = [];

  int pos = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  int acked = 0;
  int ackCalls = 0;
  bool _scheduled = false;
  bool stopped = false;

  void start() => _schedule();

  void _schedule() {
    if (_scheduled || stopped) return;
    _scheduled = true;
    Timer.run(_pump);
  }

  void _pump() {
    _scheduled = false;
    // Post several chunks per turn, like a reader thread outrunning the UI.
    for (var i = 0; i < 8; i++) {
      if (stopped || pos >= data.length || inFlight >= limit) break;
      final n = min(1 + _rng.nextInt(64 * 1024), data.length - pos);
      final chunk = Uint8List.sublistView(data, pos, pos + n);
      pos += n;
      inFlight += n;
      maxInFlight = max(maxInFlight, inFlight);
      _out.add(Uint8List.fromList(chunk));
    }
    if (pos < data.length && inFlight < limit) _schedule();
  }

  @override
  void ackBytes(int bytes) {
    ackCalls++;
    acked += bytes;
    inFlight = max(0, inFlight - bytes);
    _schedule();
  }

  @override
  Stream<List<int>> get output => _out.stream;
  @override
  void write(Uint8List d) => written.add(d);
  @override
  void resize(int rows, int cols) {}
  @override
  void kill() {}
  @override
  Future<int> get exitCode => _exit.future;
}

Uint8List _corpus(int bytes) {
  // Mixed ASCII, SGR colour, multi-byte (2/3/4 byte) text and newlines, so
  // chunk boundaries land inside sequences all the time.
  final unit = utf8.encode('plain ascii line with some words 0123456789\r\n'
      '\x1b[31mred\x1b[0m \x1b[1;32mgreen\x1b[0m café ñandú Việt Nam 日本語 😀\r\n');
  bytes -= bytes % unit.length; // end on a character boundary
  final out = Uint8List(bytes);
  for (var i = 0; i < bytes; i++) {
    out[i] = unit[i % unit.length];
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credit flow: 40 MB arrives byte-exact within the time bound',
      () async {
    final data = _corpus(40 * 1024 * 1024);
    final pty = _CreditPty(data, kLocalPtyCreditBytes);
    final svc =
        LocalShellService(ptyFactory: (shell, args, cols, rows, env) => pty);
    final session = await svc.openShell();
    final sw = Stopwatch()..start();
    pty.start();
    while (pty.acked < data.length &&
        sw.elapsed < const Duration(seconds: 150)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    svc.flushOutput(session.id);
    expect(pty.acked, data.length,
        reason: 'only ${pty.acked} of ${data.length} acked in ${sw.elapsed}');
    // Never more than the budget (plus one chunk) in flight.
    expect(pty.maxInFlight, lessThanOrEqualTo(kLocalPtyCreditBytes + 64 * 1024));
    // Batched: nowhere near one ack per chunk.
    expect(pty.ackCalls, lessThan(data.length ~/ 1024));

    final ref = Terminal(maxLines: 10000)
      ..resize(session.terminal.viewWidth, session.terminal.viewHeight)
      ..write(utf8.decode(data));
    expect(session.terminal.buffer.getText(), ref.buffer.getText());
    expect(session.terminal.buffer.lines.length, ref.buffer.lines.length);
  }, timeout: const Timeout(Duration(seconds: 200)));

  test('credit is returned for everything still queued on dispose', () async {
    final data = _corpus(8 * 1024 * 1024);
    final pty = _CreditPty(data, kLocalPtyCreditBytes);
    final svc =
        LocalShellService(ptyFactory: (shell, args, cols, rows, env) => pty);
    final session = await svc.openShell();
    pty.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final delivered = pty.pos;
    svc.closeSession(session.id);
    expect(pty.acked, delivered,
        reason: 'a native reader must never stay blocked after close');
  });

  test('Ctrl+C: output in flight after the stop is bounded by the budget',
      () async {
    final data = _corpus(64 * 1024 * 1024);
    final pty = _CreditPty(data, kLocalPtyCreditBytes);
    final svc =
        LocalShellService(ptyFactory: (shell, args, cols, rows, env) => pty);
    final session = await svc.openShell();
    pty.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // The producer is stopped (the shell got SIGINT): at most the budget (+1
    // chunk) can still be waiting, however far the UI is behind.
    pty.stopped = true;
    expect(pty.inFlight, lessThanOrEqualTo(kLocalPtyCreditBytes + 64 * 1024));
    final sw = Stopwatch()..start();
    while (pty.acked < pty.pos && sw.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pty.acked, pty.pos);
    svc.flushOutput(session.id);
  });
}
