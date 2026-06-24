/// A single line in a session's connection log — the human-readable trace of a
/// connect attempt (resolve → TCP → host-key verify → auth → shell) surfaced by
/// the "Show logs" panel on the connecting screen.
library;

enum ConnectionLogLevel { info, success, warn, error }

class ConnectionLogLine {
  final DateTime time;
  final ConnectionLogLevel level;
  final String message;

  const ConnectionLogLine({
    required this.time,
    required this.level,
    required this.message,
  });
}

/// Cap on retained connection-log lines. A flapping host with verbose reconnect
/// chatter must not grow this list without bound.
const int kMaxConnectionLogLines = 200;
