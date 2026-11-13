import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/update_service.dart';
import 'package:yourssh/widgets/notification_bell.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

/// FTappable's press feedback runs a 100 ms timer; pump past it after taps.
const _tick = Duration(milliseconds: 150);

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
        child: ysTestApp(
          Align(
            alignment: Alignment.topRight,
            child: NotificationBellBtn(
              onShowUpdateDetails: onShowUpdateDetails,
              onOpenSession: onOpenSession,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('badge hidden at zero unread', (tester) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    expect(find.byIcon(FLucideIcons.bell), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('badge shows unread count, 9+ above nine', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(type: AppNotificationType.update, title: 'one'));
    await pump(tester, center);
    expect(find.text('1'), findsOneWidget);

    for (var i = 0; i < 12; i++) {
      center.add(
        AppNotification(type: AppNotificationType.update, title: 'n$i'),
      );
    }
    await tester.pump(_tick);
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('tap opens panel, lists item, clears badge', (tester) async {
    final center = NotificationCenterProvider();
    center.add(
      AppNotification(
        type: AppNotificationType.sessionDisconnect,
        title: 'dropped',
      ),
    );
    await pump(tester, center);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('dropped'), findsOneWidget);
    expect(center.unreadCount, 0);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('empty state shows No notifications, hides Clear all', (
    tester,
  ) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.text('No notifications'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('update item: Details closes panel and fires callback', (
    tester,
  ) async {
    final center = NotificationCenterProvider();
    center.add(
      AppNotification(
        type: AppNotificationType.update,
        title: 'New version v9.9.9 available',
        dedupeKey: 'update:v9.9.9',
      ),
    );
    var details = 0;
    await pump(tester, center, onShowUpdateDetails: () => details++);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pump(_tick);
    expect(details, 1);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('update item: Update button closes the panel', (tester) async {
    final center = NotificationCenterProvider();
    center.add(
      AppNotification(
        type: AppNotificationType.update,
        title: 'New version v9.9.9 available',
        dedupeKey: 'update:v9.9.9',
      ),
    );
    await pump(tester, center);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    // downloadAndInstall() no-ops here (no release fetched), so this only
    // verifies the panel-close behavior of the button.
    await tester.tap(find.text('Update'));
    await tester.pump(_tick);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('tapping the bell again closes the panel', (tester) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('disconnect item tap fires onOpenSession with session id', (
    tester,
  ) async {
    final center = NotificationCenterProvider();
    center.add(
      AppNotification(
        type: AppNotificationType.sessionDisconnect,
        title: 'Session disconnected: web-1',
        sessionId: 'sess-42',
        dedupeKey: 'disconnect:sess-42',
      ),
    );
    String? opened;
    await pump(tester, center, onOpenSession: (id) => opened = id);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    await tester.tap(find.text('Session disconnected: web-1'));
    await tester.pump(_tick);
    expect(opened, 'sess-42');
  });

  testWidgets('Clear all empties the panel', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(type: AppNotificationType.update, title: 'one'));
    await pump(tester, center);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    await tester.tap(find.text('Clear all'));
    await tester.pump(_tick);
    expect(find.text('No notifications'), findsOneWidget);
    expect(center.notifications, isEmpty);
  });

  testWidgets('agent forwarding item: key icon, tap jumps to the session', (
    tester,
  ) async {
    final center = NotificationCenterProvider();
    center.add(
      AppNotification(
        type: AppNotificationType.agentForwarding,
        title: 'Agent forwarding refused: u@h',
        dedupeKey: 'agent-refused:s1',
        sessionId: 's1',
      ),
    );
    String? opened;
    await pump(tester, center, onOpenSession: (id) => opened = id);

    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.byIcon(FLucideIcons.keyRound), findsOneWidget);

    await tester.tap(find.text('Agent forwarding refused: u@h'));
    await tester.pump(_tick);
    expect(opened, 's1');
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('bell is a ghost FButton.icon with a Tooltip and muted glyph', (
    tester,
  ) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    expect(find.byType(FButton), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Notifications',
    );
    final icon = tester.widget<Icon>(find.byIcon(FLucideIcons.bell));
    final color =
        icon.color ??
        IconTheme.of(tester.element(find.byIcon(FLucideIcons.bell))).color;
    expect(color, YsColors.mutedForeground);
  });

  testWidgets('bell is keyboard focusable: Tab then Enter opens the panel', (
    tester,
  ) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(_tick);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(_tick);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('unread badge exposes a semantics value', (tester) async {
    final handle = tester.ensureSemantics();
    final center = NotificationCenterProvider();
    for (var i = 0; i < 3; i++) {
      center.add(
        AppNotification(
          type: AppNotificationType.update,
          title: 'n$i',
          dedupeKey: 'k$i',
        ),
      );
    }
    await pump(tester, center);
    expect(find.semantics.byValue('3 unread'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('panel uses card colour with a border edge', (tester) async {
    final center = NotificationCenterProvider();
    await pump(tester, center);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('notification-panel')),
    );
    expect(material.color, YsColors.card);
    final shape = material.shape as RoundedRectangleBorder;
    expect(shape.side.color, YsColors.border);
  });

  testWidgets('link refused item renders with its title', (tester) async {
    final center = NotificationCenterProvider();
    center.add(
      AppNotification(
        type: AppNotificationType.linkRefused,
        title: 'Link refused',
        dedupeKey: 'link-refused:1',
      ),
    );
    await pump(tester, center);
    await tester.tap(find.byIcon(FLucideIcons.bell), warnIfMissed: false);
    await tester.pump(_tick);
    expect(find.text('Link refused'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.link2Off), findsOneWidget);
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
