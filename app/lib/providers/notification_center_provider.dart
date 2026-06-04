import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';

/// In-memory store behind the notification bell in the top tab bar.
/// Sources (update available, session disconnect) push via [add]; the bell
/// badge shows [unreadCount] and opening the panel calls [markAllRead].
class NotificationCenterProvider extends ChangeNotifier {
  static const maxItems = 50;

  final List<AppNotification> _items = [];

  /// Newest first.
  List<AppNotification> get notifications => List.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.read).length;

  /// Adds [n] at the top. If [AppNotification.dedupeKey] matches an existing
  /// item, that item is replaced in place instead (the new item is unread).
  /// The list is capped at [maxItems]; oldest items drop off.
  void add(AppNotification n) {
    final key = n.dedupeKey;
    final existing =
        key == null ? -1 : _items.indexWhere((e) => e.dedupeKey == key);
    if (existing >= 0) {
      _items[existing] = n;
    } else {
      _items.insert(0, n);
      if (_items.length > maxItems) {
        _items.removeRange(maxItems, _items.length);
      }
    }
    notifyListeners();
  }

  /// Marks every item read; notifies only when something changed.
  void markAllRead() {
    var changed = false;
    for (final n in _items) {
      if (!n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Removes all items.
  void clearAll() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  /// Removes the item with [id]; no-op for unknown ids.
  void remove(String id) {
    final lengthBefore = _items.length;
    _items.removeWhere((n) => n.id == id);
    if (_items.length != lengthBefore) notifyListeners();
  }
}
