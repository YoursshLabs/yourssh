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
  final bool isWatch;
  final String? watchedTitle;
  String? customLabel;
  String? colorTag;
  bool isPinned;

  SshSession({
    String? id,
    required this.host,
    this.status = SessionStatus.connecting,
    this.errorMessage,
    DateTime? connectedAt,
    this.initialCommand,
    this.isWatch = false,
    this.watchedTitle,
    this.customLabel,
    this.colorTag,
    this.isPinned = false,
  })  : id = id ?? const Uuid().v4(),
        terminal = Terminal(maxLines: 10000),
        connectedAt = connectedAt ?? DateTime.now();

  factory SshSession.watch({required String watchedTitle}) {
    return SshSession(
      host: Host(
        id: const Uuid().v4(),
        label: '[WATCH] $watchedTitle',
        host: '',
        port: 22,
        username: '',
      ),
      status: SessionStatus.connected,
      isWatch: true,
      watchedTitle: watchedTitle,
    );
  }

  String get title =>
      customLabel ??
      (isWatch ? '[WATCH] ${watchedTitle ?? host.host}' : '${host.username}@${host.host}');

  /// Label shown on the session tab: the user's custom rename, falling back to
  /// the host's display label (the watch factory stores '[WATCH] …' there).
  String get tabLabel => customLabel ?? host.label;

  String get statusLabel => switch (status) {
        SessionStatus.connecting => 'Connecting...',
        SessionStatus.connected => isWatch ? 'Watching' : 'Connected',
        SessionStatus.disconnected => 'Disconnected',
        SessionStatus.error => errorMessage ?? 'Error',
      };
}
