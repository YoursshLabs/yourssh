import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';

AppNotification _n(String title, {String? dedupeKey}) => AppNotification(
      type: AppNotificationType.update,
      title: title,
      dedupeKey: dedupeKey,
    );

void main() {
  group('NotificationCenterProvider', () {
    late NotificationCenterProvider p;
    setUp(() => p = NotificationCenterProvider());
    tearDown(() => p.dispose());

    test('starts empty with zero unread', () {
      expect(p.notifications, isEmpty);
      expect(p.unreadCount, 0);
    });

    test('add prepends newest first and counts unread', () {
      p.add(_n('first'));
      p.add(_n('second'));
      expect(p.notifications.map((n) => n.title).toList(), ['second', 'first']);
      expect(p.unreadCount, 2);
    });

    test('add with matching dedupeKey replaces in place as unread', () {
      p.add(_n('v1', dedupeKey: 'update:v1'));
      p.add(_n('other'));
      p.markAllRead();
      p.add(_n('v1 again', dedupeKey: 'update:v1'));
      expect(p.notifications.length, 2);
      // Replaced item keeps its original position (index 1).
      expect(p.notifications[1].title, 'v1 again');
      expect(p.unreadCount, 1);
    });

    test('markAllRead zeroes unread, notifies once, no-op when nothing unread', () {
      p.add(_n('a'));
      p.add(_n('b'));
      var notifies = 0;
      p.addListener(() => notifies++);
      p.markAllRead();
      expect(p.unreadCount, 0);
      expect(notifies, 1);
      p.markAllRead();
      expect(notifies, 1);
    });

    test('clearAll empties the list', () {
      p.add(_n('a'));
      p.clearAll();
      expect(p.notifications, isEmpty);
      expect(p.unreadCount, 0);
    });

    test('remove deletes by id, ignores unknown id', () {
      p.add(_n('a'));
      final id = p.notifications.first.id;
      p.remove('nope');
      expect(p.notifications.length, 1);
      p.remove(id);
      expect(p.notifications, isEmpty);
    });

    test('list is capped at maxItems, oldest dropped', () {
      for (var i = 0; i < NotificationCenterProvider.maxItems + 5; i++) {
        p.add(_n('item $i'));
      }
      expect(p.notifications.length, NotificationCenterProvider.maxItems);
      expect(p.notifications.first.title,
          'item ${NotificationCenterProvider.maxItems + 4}');
      expect(p.notifications.last.title, 'item 5');
    });
  });
}
