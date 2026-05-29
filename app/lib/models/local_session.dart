// app/lib/models/local_session.dart
import 'dart:io';
import 'package:xterm/xterm.dart';
import 'package:uuid/uuid.dart';

enum LocalSessionStatus { running, exited, error }

class LocalSession {
  final String id;
  final Terminal terminal;
  LocalSessionStatus status;
  String? errorMessage;
  Process? _process;

  LocalSession({
    required this.terminal,
    this.status = LocalSessionStatus.running,
  }) : id = const Uuid().v4();

  void attachProcess(Process process) {
    _process = process;
  }

  void kill() {
    _process?.kill();
    status = LocalSessionStatus.exited;
  }
}
