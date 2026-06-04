// app/test/services/local_shell_service_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/services/local_shell_service.dart';
import 'package:yourssh/services/pty_runner.dart';
import 'package:yourssh/services/recording_service.dart';

class FakePtyRunner implements PtyRunner {
  final _outputController = StreamController<List<int>>.broadcast();
  final _exitCompleter = Completer<int>();
  final List<Uint8List> written = [];
  final List<({int rows, int cols})> resizes = [];
  bool killed = false;

  @override
  Stream<List<int>> get output => _outputController.stream;

  @override
  void write(Uint8List data) => written.add(data);

  @override
  void resize(int rows, int cols) => resizes.add((rows: rows, cols: cols));

  @override
  void kill() => killed = true;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  void emitOutput(List<int> bytes) => _outputController.add(bytes);
  void completeExit(int code) => _exitCompleter.complete(code);
  void dispose() => _outputController.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePtyRunner fakePty;
  late LocalShellService service;

  setUp(() {
    fakePty = FakePtyRunner();
    service = LocalShellService(
      ptyFactory: (shell, cols, rows, env) => fakePty,
    );
  });

  tearDown(() => fakePty.dispose());

  group('LocalShellService', () {
    test('openShell returns a running session', () async {
      final session = await service.openShell();
      expect(session.status, LocalSessionStatus.running);
    });

    test('openShell stores session, getSession returns it', () async {
      final session = await service.openShell();
      expect(service.getSession(session.id), same(session));
    });

    test('pty output is piped to terminal without throwing', () async {
      final session = await service.openShell();
      fakePty.emitOutput(utf8.encode('hello'));
      await Future<void>.delayed(Duration.zero);
      expect(session.status, LocalSessionStatus.running);
    });

    test('terminal onOutput sends encoded bytes to pty', () async {
      final session = await service.openShell();
      session.terminal.onOutput?.call('hi');
      expect(fakePty.written, hasLength(1));
      expect(utf8.decode(fakePty.written.first), 'hi');
    });

    test('terminal onResize calls pty.resize with swapped rows/cols', () async {
      final session = await service.openShell();
      // onResize signature: (w, h, pw, ph) → pty.resize(h, w)
      session.terminal.onResize?.call(120, 40, 0, 0);
      expect(fakePty.resizes, hasLength(1));
      expect(fakePty.resizes.first.rows, 40);
      expect(fakePty.resizes.first.cols, 120);
    });

    test('pty exit sets session status to exited', () async {
      final session = await service.openShell();
      fakePty.completeExit(0);
      await Future<void>.delayed(Duration.zero);
      expect(session.status, LocalSessionStatus.exited);
    });

    test('closeSession kills the pty and removes session', () async {
      final session = await service.openShell();
      service.closeSession(session.id);
      expect(fakePty.killed, true);
      expect(service.getSession(session.id), isNull);
    });

    test('factory error sets session to error state with message', () async {
      final badService = LocalShellService(
        ptyFactory: (_, _, _, _) => throw Exception('pty unavailable'),
      );
      final session = await badService.openShell();
      expect(session.status, LocalSessionStatus.error);
      expect(session.errorMessage, contains('pty unavailable'));
    });
  });

  group('recording intercept', () {
    test('pty output is forwarded to RecordingService', () async {
      final dir = await Directory.systemTemp.createTemp('ys_rec');
      addTearDown(() => dir.delete(recursive: true));

      final rec = RecordingService();
      service.recordingService = rec;

      final session = await service.openShell();
      await rec.startRecording(
        session.id,
        filePath: '${dir.path}/local/session_test.cast',
        width: 80,
        height: 24,
        title: 'Local terminal',
      );

      fakePty.emitOutput(utf8.encode('hello-from-pty'));
      await Future<void>.delayed(Duration.zero);

      final path = await rec.stopRecording(session.id);
      expect(path, isNotNull);
      final content = await File(path!).readAsString();
      expect(content, contains('hello-from-pty'));
    });
  });

  group('resolveShell', () {
    test('windows: defaults to powershell.exe, never a unix shell', () {
      expect(
        LocalShellService.resolveShell({}, isWindows: true),
        'powershell.exe',
      );
    });

    test('windows: ignores SHELL even if set (e.g. by git-bash)', () {
      expect(
        LocalShellService.resolveShell(
          {'SHELL': '/usr/bin/bash'},
          isWindows: true,
        ),
        'powershell.exe',
      );
    });

    test('unix: uses SHELL when set', () {
      expect(
        LocalShellService.resolveShell({'SHELL': '/bin/bash'}, isWindows: false),
        '/bin/bash',
      );
    });

    test('unix: falls back to /bin/zsh', () {
      expect(
        LocalShellService.resolveShell({}, isWindows: false),
        '/bin/zsh',
      );
    });
  });
}
