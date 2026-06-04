// app/lib/services/local_shell_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

  /// Picks the shell executable for the current platform. On Windows `SHELL`
  /// is never set by the OS (and may point to a unix path under git-bash), so
  /// ConPTY needs a Windows executable — PowerShell ships with every
  /// Win10/11 and aliases ls/cat/rm, so it beats cmd.exe as the default.
  @visibleForTesting
  static String resolveShell(Map<String, String> env, {required bool isWindows}) {
    if (isWindows) return 'powershell.exe';
    return env['SHELL'] ?? '/bin/zsh';
  }

  Future<LocalSession> openShell() async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal);
    _sessions[session.id] = session;
    _spawnPty(session);
    return session;
  }

  /// Re-runs the PTY spawn on an exited/errored session, reusing its terminal
  /// (and scrollback). Used by the local pane's "Restart shell" button.
  Future<void> restartShell(LocalSession session) async {
    if (session.status == LocalSessionStatus.running) return;
    session.status = LocalSessionStatus.running;
    session.errorMessage = null;
    _spawnPty(session);
  }

  void _spawnPty(LocalSession session) {
    final terminal = session.terminal;
    final shell =
        resolveShell(Platform.environment, isWindows: Platform.isWindows);

    try {
      final pty = _ptyFactory(
        shell,
        terminal.viewWidth,
        terminal.viewHeight,
        {...Platform.environment, 'TERM': 'xterm-256color'},
      );

      session.attachPty(pty);

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
            } catch (e) {
              debugPrint('[LocalShellService] notification handler threw: $e');
            }
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
  }

  void closeSession(String sessionId) {
    _sessions[sessionId]?.kill();
    _sessions.remove(sessionId);
    NotificationService.instance.removeSession(sessionId);
  }

  LocalSession? getSession(String sessionId) => _sessions[sessionId];
}
