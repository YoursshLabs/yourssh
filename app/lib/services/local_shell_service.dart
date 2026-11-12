// app/lib/services/local_shell_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';
import '../models/shell_profile.dart';
import 'notification_service.dart';
import 'pty_runner.dart';
import 'recording_service.dart';
import 'terminal_write_queue.dart';

typedef PtyFactory = PtyRunner Function(
  String shell,
  List<String> args,
  int columns,
  int rows,
  Map<String, String> environment,
);

class LocalShellService {
  final Map<String, LocalSession> _sessions = {};
  final PtyFactory _ptyFactory;

  /// Passive intercept (same pattern as SshService): set by main.dart,
  /// no-ops when the session is not being recorded.
  RecordingService? recordingService;

  /// Fired whenever a session's status changes outside a provider call
  /// (PTY exit, spawn failure). LocalSession is not observable, so without
  /// this the UI never learns the shell died and the "Restart shell" view
  /// stays unreachable. Wired to SessionProvider's notify by its
  /// `localShell` setter.
  void Function()? onSessionStateChanged;

  final Map<String, TerminalWriteQueue> _queues = {};

  /// Synchronously drains pending output of [sessionId] into its terminal
  /// (ordering barrier; used by tests and before out-of-band writes).
  void flushOutput(String sessionId) => _queues[sessionId]?.flush();

  LocalShellService({PtyFactory? ptyFactory})
      : _ptyFactory = ptyFactory ?? _defaultFactory;

  static PtyRunner _defaultFactory(
    String shell,
    List<String> args,
    int columns,
    int rows,
    Map<String, String> environment,
  ) =>
      FlutterPtyRunner(
        Pty.start(shell,
            arguments: args,
            columns: columns,
            rows: rows,
            environment: environment,
            ackRead: true),
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

  Future<LocalSession> openShell({ShellProfile? profile}) async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal, profile: profile);
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
    final profile = session.profile;
    final shell = profile?.executable ??
        resolveShell(Platform.environment, isWindows: Platform.isWindows);
    final args = profile?.args ?? const <String>[];

    try {
      final pty = _ptyFactory(
        shell,
        args,
        terminal.viewWidth,
        terminal.viewHeight,
        {...Platform.environment, 'TERM': 'xterm-256color'},
      );

      session.attachPty(pty);

      _queues.remove(session.id)?.dispose();
      final queue = TerminalWriteQueue(
        write: terminal.writeNoNotify,
        commit: terminal.flushWrites,
        onBatch: (batch) {
          recordingService?.writeOutput(session.id, batch);
          try {
            NotificationService.instance.onTerminalData(
              batch,
              sessionId: session.id,
              sessionLabel: 'Local Shell',
            );
          } catch (e) {
            debugPrint('[LocalShellService] notification handler threw: $e');
          }
        },
      );
      _queues[session.id] = queue;

      // With ackRead the native reader blocks until each chunk is acked; ack
      // as soon as the queue starts consuming the chunk (one chunk of
      // read-ahead), so the shell stalls when the UI is behind.
      final ackable = pty is AckablePty ? pty as AckablePty : null;
      final decoder = const Utf8Decoder(allowMalformed: true);
      var decoded = '';
      // Stateful decoding (multi-byte sequences may straddle chunks).
      final byteSink =
          decoder.startChunkedConversion(_CollectingSink((s) => decoded += s));
      pty.output.listen((bytes) {
        decoded = '';
        byteSink.add(bytes);
        if (decoded.isEmpty) {
          ackable?.ackRead();
        } else {
          queue.add(decoded, onTaken: ackable?.ackRead);
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
        _queues.remove(session.id)?.flush();
        terminal.write('\r\n[Process exited with code $code]\r\n');
        recordingService?.onShellClosed(session.id);
        NotificationService.instance.removeSession(session.id);
        onSessionStateChanged?.call();
      });
    } catch (e) {
      session.status = LocalSessionStatus.error;
      session.errorMessage = e.toString();
      onSessionStateChanged?.call();
    }
  }

  void closeSession(String sessionId) {
    recordingService?.onShellClosed(sessionId);
    _sessions[sessionId]?.kill();
    _sessions.remove(sessionId);
    _queues.remove(sessionId)?.dispose();
    NotificationService.instance.removeSession(sessionId);
  }

  LocalSession? getSession(String sessionId) => _sessions[sessionId];
}

class _CollectingSink implements Sink<String> {
  _CollectingSink(this._onData);
  final void Function(String) _onData;
  @override
  void add(String data) => _onData(data);
  @override
  void close() {}
}
