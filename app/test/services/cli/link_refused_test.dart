import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
import 'package:yourssh/services/cli/link_refused.dart';

void main() {
  test('a refused link becomes a sanitized bell entry', () {
    final n = linkRefusedNotification(
        'yourssh://connect/x\x1b[31m\u202E\x85y', 'unknown host: x\x07y');
    expect(n.type, AppNotificationType.linkRefused);
    expect(n.title, 'Link refused: yourssh://connect/x[31my');
    expect(n.body, 'unknown host: xy');
  });

  test('a very long link is shortened', () {
    final n = linkRefusedNotification(
        'yourssh://connect/${'a' * 500}', 'unknown host');
    expect(n.title.length, lessThan(160));
    expect(n.title, endsWith('…'));
  });

  test('the same link refused twice is one entry (deduped)', () {
    final center = NotificationCenterProvider();
    addTearDown(center.dispose);
    center.add(linkRefusedNotification('yourssh://connect/nope', 'a'));
    center.add(linkRefusedNotification('YOURSSH://connect/nope', 'b'));
    center.add(linkRefusedNotification('yourssh://connect/other', 'c'));
    expect(center.notifications, hasLength(2));
  });
}
