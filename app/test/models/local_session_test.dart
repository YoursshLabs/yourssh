// app/test/models/local_session_test.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/models/terminal_session.dart';
import 'package:yourssh/services/pty_runner.dart';

class FakePtyRunner implements PtyRunner {
  final _outputController = StreamController<List<int>>();
  final _exitCompleter = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int cols) {}

  @override
  void kill() => killed = true;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  void dispose() => _outputController.close();
}

void main() {
  group('LocalSession', () {
    test('initial status is running', () {
      final session = LocalSession(terminal: Terminal());
      expect(session.status, LocalSessionStatus.running);
    });

    test('kill() sets status to exited', () {
      final session = LocalSession(terminal: Terminal());
      session.kill();
      expect(session.status, LocalSessionStatus.exited);
    });

    test('kill() calls kill on attached PtyRunner', () {
      final session = LocalSession(terminal: Terminal());
      final fake = FakePtyRunner();
      session.attachPty(fake);
      session.kill();
      expect(fake.killed, true);
      fake.dispose();
    });

    test('kill() without attachPty does not throw', () {
      final session = LocalSession(terminal: Terminal());
      expect(() => session.kill(), returnsNormally);
    });

    test('each session has a unique id', () {
      final a = LocalSession(terminal: Terminal());
      final b = LocalSession(terminal: Terminal());
      expect(a.id, isNot(equals(b.id)));
    });

    test('tabLabel defaults to "Local N" with increasing N', () {
      final a = LocalSession(terminal: Terminal());
      final b = LocalSession(terminal: Terminal());
      final re = RegExp(r'^Local (\d+)$');
      final ma = re.firstMatch(a.tabLabel)!;
      final mb = re.firstMatch(b.tabLabel)!;
      expect(int.parse(mb.group(1)!), int.parse(ma.group(1)!) + 1);
    });

    test('customLabel overrides default tabLabel', () {
      final s = LocalSession(terminal: Terminal());
      s.customLabel = 'build box';
      expect(s.tabLabel, 'build box');
    });

    test('implements TerminalSession with isLocal true', () {
      final TerminalSession s = LocalSession(terminal: Terminal());
      expect(s.isLocal, isTrue);
      expect(s.isPinned, isFalse);
      expect(s.colorTag, isNull);
    });
  });
}
