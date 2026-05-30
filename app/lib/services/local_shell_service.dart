// app/lib/services/local_shell_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';
import 'notification_service.dart';
import 'pty_runner.dart';

typedef PtyFactory = PtyRunner Function(
  String shell,
  int columns,
  int rows,
  Map<String, String> environment,
);

class LocalShellService {
  final Map<String, LocalSession> _sessions = {};
  final PtyFactory _ptyFactory;

  LocalShellService({PtyFactory? ptyFactory})
      : _ptyFactory = ptyFactory ?? _defaultFactory;

  static PtyRunner _defaultFactory(
    String shell,
    int columns,
    int rows,
    Map<String, String> environment,
  ) =>
      FlutterPtyRunner(
        Pty.start(shell, columns: columns, rows: rows, environment: environment),
      );

  Future<LocalSession> openShell() async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal);

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';

    try {
      final pty = _ptyFactory(
        shell,
        terminal.viewWidth,
        terminal.viewHeight,
        {...Platform.environment, 'TERM': 'xterm-256color'},
      );

      session.attachPty(pty);
      _sessions[session.id] = session;

      pty.output
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            terminal.write(data);
            try {
              NotificationService.instance.onTerminalData(
                data,
                sessionId: session.id,
                sessionLabel: 'Local Shell',
              );
            } catch (_) {}
          });

      terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };

      terminal.onResize = (w, h, pw, ph) {
        pty.resize(h, w);
      };

      pty.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
        NotificationService.instance.removeSession(session.id);
      });
    } catch (e) {
      session.status = LocalSessionStatus.error;
      session.errorMessage = e.toString();
    }

    return session;
  }

  void closeSession(String sessionId) {
    _sessions[sessionId]?.kill();
    _sessions.remove(sessionId);
    NotificationService.instance.removeSession(sessionId);
  }

  LocalSession? getSession(String sessionId) => _sessions[sessionId];
}
