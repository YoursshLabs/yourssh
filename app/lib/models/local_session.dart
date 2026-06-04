// app/lib/models/local_session.dart
import 'package:xterm/xterm.dart';
import 'package:uuid/uuid.dart';
import '../services/pty_runner.dart';
import 'terminal_session.dart';

enum LocalSessionStatus { running, exited, error }

class LocalSession implements TerminalSession {
  /// Monotonic per-app-run counter for default "Local N" tab labels.
  static int _labelCounter = 0;

  @override
  final String id;
  @override
  final Terminal terminal;
  LocalSessionStatus status;
  String? errorMessage;
  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned;
  final int _labelIndex;
  PtyRunner? _pty;

  LocalSession({
    required this.terminal,
    this.status = LocalSessionStatus.running,
    this.customLabel,
    this.colorTag,
    this.isPinned = false,
  })  : id = const Uuid().v4(),
        _labelIndex = ++_labelCounter;

  @override
  String get tabLabel => customLabel ?? 'Local $_labelIndex';

  @override
  bool get isLocal => true;

  void attachPty(PtyRunner pty) {
    _pty = pty;
  }

  void kill() {
    _pty?.kill();
    status = LocalSessionStatus.exited;
  }
}
