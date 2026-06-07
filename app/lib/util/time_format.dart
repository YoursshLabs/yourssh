/// Tiny shared time formatting helpers — the canonical home for the
/// zero-pad-2 pattern that keeps getting re-implemented per screen.
String pad2(int v) => v.toString().padLeft(2, '0');

/// `yyyy-MM-dd HH:mm:ss` in local time.
String formatLocalTimestamp(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${pad2(l.month)}-${pad2(l.day)} '
      '${pad2(l.hour)}:${pad2(l.minute)}:${pad2(l.second)}';
}
