import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/update_service.dart';
import 'package:yourssh/widgets/notification_bell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester,
    NotificationCenterProvider center, {
    VoidCallback? onShowUpdateDetails,
    void Function(String)? onOpenSession,
  }) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: center),
          ChangeNotifierProvider(
            create: (_) =>
                UpdateProvider(UpdateService(), currentVersion: '0.0.0'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: NotificationBellBtn(
                onShowUpdateDetails: onShowUpdateDetails,
                onOpenSession: onOpenSession,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('badge hidden at zero unread', (tester) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('badge shows unread count, 9+ above nine', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(type: AppNotificationType.update, title: 'one'));
    await pump(tester, center);
    expect(find.text('1'), findsOneWidget);

    for (var i = 0; i < 12; i++) {
      center.add(
          AppNotification(type: AppNotificationType.update, title: 'n$i'));
    }
    await tester.pump();
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('tap opens panel, lists item, clears badge', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(
        type: AppNotificationType.sessionDisconnect, title: 'dropped'));
    await pump(tester, center);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('dropped'), findsOneWidget);
    expect(center.unreadCount, 0);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('empty state shows No notifications, hides Clear all',
      (tester) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    expect(find.text('No notifications'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('update item: Details closes panel and fires callback',
      (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(
      type: AppNotificationType.update,
      title: 'New version v9.9.9 available',
      dedupeKey: 'update:v9.9.9',
    ));
    var details = 0;
    await pump(tester, center, onShowUpdateDetails: () => details++);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(details, 1);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('update item: Update button closes the panel', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(
      type: AppNotificationType.update,
      title: 'New version v9.9.9 available',
      dedupeKey: 'update:v9.9.9',
    ));
    await pump(tester, center);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    // downloadAndInstall() no-ops here (no release fetched), so this only
    // verifies the panel-close behavior of the button.
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('tapping the bell again closes the panel', (tester) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('disconnect item tap fires onOpenSession with session id',
      (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(
      type: AppNotificationType.sessionDisconnect,
      title: 'Session disconnected: web-1',
      sessionId: 'sess-42',
      dedupeKey: 'disconnect:sess-42',
    ));
    String? opened;
    await pump(tester, center, onOpenSession: (id) => opened = id);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Session disconnected: web-1'));
    await tester.pump();
    expect(opened, 'sess-42');
  });

  testWidgets('Clear all empties the panel', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(type: AppNotificationType.update, title: 'one'));
    await pump(tester, center);
    await tester.tap(find.byIcon(Icons.notifications_none), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('No notifications'), findsOneWidget);
    expect(center.notifications, isEmpty);
  });

  group('relativeTime', () {
    test('formats each bucket', () {
      final now = DateTime.now();
      expect(relativeTime(now), 'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5))), '5m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3))), '3h ago');
      expect(relativeTime(now.subtract(const Duration(days: 2))), '2d ago');
    });
  });
}
