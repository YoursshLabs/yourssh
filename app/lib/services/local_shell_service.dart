// app/lib/services/local_shell_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';

class LocalShellService {
  final Map<String, LocalSession> _sessions = {};

  Future<LocalSession> openShell() async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal);

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';

    try {
      final process = await Process.start(
        shell,
        [],
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
        },
        runInShell: false,
      );

      session.attachProcess(process);
      _sessions[session.id] = session;

      // Process stdout -> terminal
      process.stdout.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Process stderr -> terminal
      process.stderr.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Terminal input -> process stdin
      terminal.onOutput = (data) {
        process.stdin.add(utf8.encode(data));
      };

      // Handle process exit
      process.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
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
  }

  LocalSession? getSession(String sessionId) => _sessions[sessionId];
}
