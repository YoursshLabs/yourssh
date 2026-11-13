// 19 notifications: items in the bell.
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
import 'nav.dart';
import 'sections.dart';

const s = '19-notifications';

Future<void> runNotifications(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Hosts');
  final nc = c.read<NotificationCenterProvider>();
  nc.add(AppNotification(
      type: AppNotificationType.update,
      title: 'Update available: v9.9.9',
      body: 'A new version of YourSSH is ready to download.',
      dedupeKey: 'update:v9.9.9'));
  nc.add(AppNotification(
      type: AppNotificationType.sessionDisconnect,
      title: 'Demo Key Auth disconnected',
      body: 'Connection closed by the server.',
      dedupeKey: 'disconnect:docs'));
  c.notes.add('19: the bell items were added through NotificationCenterProvider.add (same API the app uses for update/disconnect events) so the open bell can be shown without a real GitHub release or a forced drop.');
  await sleepPump(t, 500);
  await c.snap('$s/01-bell-badge', 'Bell with an unread badge');
  await tapTooltip(t, 'Notifications', wait: 700);
  await c.snap('$s/02-bell-open', 'Notification panel: update and disconnect items');
  await pressEscape(t);
}
