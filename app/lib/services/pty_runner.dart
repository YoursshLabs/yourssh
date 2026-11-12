// app/lib/services/pty_runner.dart
import 'dart:typed_data';
import 'package:flutter_pty/flutter_pty.dart';

abstract class PtyRunner {
  Stream<List<int>> get output;
  void write(Uint8List data);
  void resize(int rows, int cols);
  void kill();
  Future<int> get exitCode;
}

/// Optional capability of a [PtyRunner]: the native reader waits for
/// [ackRead] after every chunk before reading more, so a shell that outputs
/// faster than the app can parse blocks in `write(2)` instead of flooding the
/// UI isolate (and reacts to Ctrl+C promptly).
abstract class AckablePty {
  void ackRead();
}

/// Credit based flow control: the native reader may keep up to the credit
/// budget in flight and blocks only beyond it. Return credit with [ackBytes]
/// by the number of bytes processed (batched, e.g. once per parse slice).
abstract class CreditPty {
  void ackBytes(int bytes);
}

class FlutterPtyRunner implements PtyRunner, AckablePty, CreditPty {
  final Pty _pty;
  FlutterPtyRunner(this._pty);

  @override
  Stream<List<int>> get output => _pty.output.cast<List<int>>();

  @override
  void write(Uint8List data) => _pty.write(data);

  @override
  void resize(int rows, int cols) => _pty.resize(rows, cols);

  @override
  void ackRead() => _pty.ackRead();

  @override
  void ackBytes(int bytes) => _pty.ackBytes(bytes);

  @override
  void kill() => _pty.kill();

  @override
  Future<int> get exitCode => _pty.exitCode;
}
