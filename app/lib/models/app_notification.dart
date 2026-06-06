/// In-app notification types surfaced by the bell in the top tab bar.
enum AppNotificationType { update, sessionDisconnect, agentForwarding }

/// One item in the in-app notification center. In-memory only — not
/// persisted across restarts (the debounced update check recreates the
/// update item on next launch).
class AppNotification {
  AppNotification({
    required this.type,
    required this.title,
    this.body,
    this.dedupeKey,
    this.sessionId,
    DateTime? timestamp,
  })  : id = 'n${_seq++}',
        timestamp = timestamp ?? DateTime.now();

  static int _seq = 0;

  final String id;
  final AppNotificationType type;
  final String title;
  final String? body;
  final DateTime timestamp;

  /// When set, [add] replaces an existing item with the same key instead of
  /// appending a duplicate (e.g. `update:v0.1.25`, `disconnect:<sessionId>`,
  /// `agent-refused:<sessionId>`).
  final String? dedupeKey;

  /// For [AppNotificationType.sessionDisconnect]: the dropped session's id,
  /// so the panel can jump back to that tab.
  final String? sessionId;

  bool read = false;
}
