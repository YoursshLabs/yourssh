import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';
import 'host.dart';

enum SessionStatus { connecting, connected, disconnected, error }

class SshSession {
  final String id;
  final Host host;
  final Terminal terminal;
  SessionStatus status;
  String? errorMessage;
  DateTime connectedAt;
  final String? initialCommand;

  SshSession({
    String? id,
    required this.host,
    this.status = SessionStatus.connecting,
    this.errorMessage,
    DateTime? connectedAt,
    this.initialCommand,
  })  : id = id ?? const Uuid().v4(),
        terminal = Terminal(maxLines: 10000),
        connectedAt = connectedAt ?? DateTime.now();

  String get title => '${host.username}@${host.host}';

  String get statusLabel => switch (status) {
        SessionStatus.connecting => 'Connecting...',
        SessionStatus.connected => 'Connected',
        SessionStatus.disconnected => 'Disconnected',
        SessionStatus.error => errorMessage ?? 'Error',
      };
}
