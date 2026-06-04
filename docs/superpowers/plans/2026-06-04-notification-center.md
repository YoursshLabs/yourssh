# Notification Center (Bell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a notification bell with unread badge next to the `+` button in the top tab bar, opening an anchored popover that lists update-available and session-disconnect notifications.

**Architecture:** A new in-memory `NotificationCenterProvider` (ChangeNotifier) stores `AppNotification` items with dedupe keys. Sources push into it from `main.dart` wiring: a listener on `UpdateProvider` (update available) and a new `onSessionDropped` callback on `SessionProvider` (session drops). A `NotificationBellBtn` widget in `_TopTabBar` renders the badge and an `OverlayPortal`-anchored panel. The existing `UpdateBanner` is kept unchanged.

**Tech Stack:** Flutter (provider package, OverlayPortal/CompositedTransformFollower/TapRegion), flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-04-notification-center-design.md`

**Conventions:** All commands run from `app/`. Commit messages follow the repo's `feat(scope):` style. All code/comments in English.

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/models/app_notification.dart` | Create | `AppNotificationType` enum + `AppNotification` model |
| `app/lib/providers/notification_center_provider.dart` | Create | In-memory store: add/dedupe/markAllRead/clearAll/remove/cap |
| `app/lib/widgets/notification_bell.dart` | Create | Bell button + badge + anchored popover panel |
| `app/lib/providers/session_provider.dart` | Modify | New `onSessionDropped` callback, fired at the two drop points |
| `app/lib/main.dart` | Modify | Create provider, wire update listener + session callback, expose via MultiProvider, dispose |
| `app/lib/screens/main_screen.dart` | Modify | Mount bell in `_TopTabBar`, pass navigation callbacks |
| `app/test/providers/notification_center_provider_test.dart` | Create | Provider unit tests |
| `app/test/providers/session_provider_test.dart` | Modify | `onSessionDropped` test |
| `app/test/widgets/notification_bell_test.dart` | Create | Bell/panel widget tests |

---

### Task 1: AppNotification model + NotificationCenterProvider

**Files:**
- Create: `app/lib/models/app_notification.dart`
- Create: `app/lib/providers/notification_center_provider.dart`
- Test: `app/test/providers/notification_center_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/providers/notification_center_provider_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/notification_center_provider_test.dart`
Expected: FAIL — `Target of URI doesn't exist` (model and provider files missing).

- [ ] **Step 3: Implement the model**

Create `app/lib/models/app_notification.dart`:

```dart
/// In-app notification types surfaced by the bell in the top tab bar.
enum AppNotificationType { update, sessionDisconnect }

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
  /// appending a duplicate (e.g. `update:v0.1.25`, `disconnect:<sessionId>`).
  final String? dedupeKey;

  /// For [AppNotificationType.sessionDisconnect]: the dropped session's id,
  /// so the panel can jump back to that tab.
  final String? sessionId;

  bool read = false;
}
```

- [ ] **Step 4: Implement the provider**

Create `app/lib/providers/notification_center_provider.dart`:

```dart
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

  void clearAll() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  void remove(String id) {
    final lengthBefore = _items.length;
    _items.removeWhere((n) => n.id == id);
    if (_items.length != lengthBefore) notifyListeners();
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/notification_center_provider_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/app_notification.dart app/lib/providers/notification_center_provider.dart app/test/providers/notification_center_provider_test.dart
git commit -m "feat(notifications): AppNotification model + NotificationCenterProvider"
```

---

### Task 2: SessionProvider.onSessionDropped callback

**Files:**
- Modify: `app/lib/providers/session_provider.dart` (field near line 27, fire points near lines 150–172)
- Test: `app/test/providers/session_provider_test.dart`

- [ ] **Step 1: Write the failing test**

In `app/test/providers/session_provider_test.dart`, add inside the existing `group('SessionProvider', ...)` (after the `'dispose during in-flight connect does not throw'` test):

```dart
    test('onSessionDropped fires with reason when connect fails and auto-reconnect is off', () async {
      final host = Host(
        label: 'unreachable',
        host: '127.0.0.1',
        port: 1,
        username: 'x',
      );
      SshSession? dropped;
      String? reason;
      provider.onSessionDropped = (s, r) {
        dropped = s;
        reason = r;
      };
      // autoReconnectEnabled left unset -> defaults to false -> error path.
      await provider.connect(host);
      expect(provider.sshSessions.first.status, SessionStatus.error);
      expect(dropped, same(provider.sshSessions.first));
      expect(reason, isNotNull);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/session_provider_test.dart --name "onSessionDropped"`
Expected: FAIL — `The setter 'onSessionDropped' isn't defined`.

- [ ] **Step 3: Implement the callback**

In `app/lib/providers/session_provider.dart`, after the `recordingStart` field (line 27):

```dart
  /// Fired when a session drops without a pending auto-reconnect: shell
  /// closed (a graceful `exit` is indistinguishable here — see spec caveat)
  /// or reconnect attempts exhausted. Wired in main.dart to the
  /// notification center.
  void Function(SshSession session, String? reason)? onSessionDropped;
```

In `_doConnect`, modify the shell-closed branch (currently lines 153–156):

```dart
      } else if (_sessions.contains(session)) {
        session.status = SessionStatus.disconnected;
        onSessionDropped?.call(session, null);
        _safeNotify();
      }
```

And the reconnect-exhausted branch (currently lines 165–171):

```dart
      } else {
        session.status = SessionStatus.error;
        session.errorMessage = attempt > 1
            ? 'Failed after $attempt attempts: $e'
            : e.toString();
        onSessionDropped?.call(session, session.errorMessage);
        _safeNotify();
      }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/session_provider_test.dart`
Expected: PASS (all existing tests + the new one).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_test.dart
git commit -m "feat(sessions): onSessionDropped callback for unexpected drops"
```

---

### Task 3: NotificationBellBtn widget + popover panel

**Files:**
- Create: `app/lib/widgets/notification_bell.dart`
- Test: `app/test/widgets/notification_bell_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `app/test/widgets/notification_bell_test.dart`:

```dart
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

    await tester.tap(find.byIcon(Icons.notifications_none));
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
    await tester.tap(find.byIcon(Icons.notifications_none));
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
    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.pump();
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(details, 1);
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
    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.pump();
    await tester.tap(find.text('Session disconnected: web-1'));
    await tester.pump();
    expect(opened, 'sess-42');
  });

  testWidgets('Clear all empties the panel', (tester) async {
    final center = NotificationCenterProvider();
    center.add(AppNotification(type: AppNotificationType.update, title: 'one'));
    await pump(tester, center);
    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.pump();
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('No notifications'), findsOneWidget);
    expect(center.notifications, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/notification_bell_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/widgets/notification_bell.dart'`.

- [ ] **Step 3: Implement the widget**

Create `app/lib/widgets/notification_bell.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/theme/app_theme.dart';

/// Bell button at the right end of the top tab bar. Shows an unread badge
/// and toggles an anchored popover listing in-app notifications.
class NotificationBellBtn extends StatefulWidget {
  const NotificationBellBtn({
    super.key,
    this.onShowUpdateDetails,
    this.onOpenSession,
  });

  /// Navigates to the Settings update section (same as the update banner).
  final VoidCallback? onShowUpdateDetails;

  /// Activates the session tab for a disconnect notification.
  final void Function(String sessionId)? onOpenSession;

  @override
  State<NotificationBellBtn> createState() => _NotificationBellBtnState();
}

class _NotificationBellBtnState extends State<NotificationBellBtn> {
  /// Shared TapRegion group: clicking the bell while the panel is open must
  /// not count as "outside" (which would close and immediately re-open it).
  static const _tapGroup = 'notification-bell-popover';

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _hovered = false;

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      // Opening the panel marks everything read — the badge clears.
      context.read<NotificationCenterProvider>().markAllRead();
      _portal.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread =
        context.select<NotificationCenterProvider, int>((p) => p.unreadCount);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Positioned(
          width: 320,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              groupId: _tapGroup,
              onTapOutside: (_) => _portal.hide(),
              child: _NotificationPanel(
                onShowUpdateDetails: widget.onShowUpdateDetails,
                onOpenSession: widget.onOpenSession,
                onClose: _portal.hide,
              ),
            ),
          ),
        ),
        child: TapRegion(
          groupId: _tapGroup,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 36,
                height: 38,
                alignment: Alignment.center,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 16,
                      color: _hovered
                          ? const Color(0xFFAAAAAA)
                          : const Color(0xFF555555),
                    ),
                    if (unread > 0)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 14),
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.onShowUpdateDetails,
    required this.onOpenSession,
    required this.onClose,
  });

  final VoidCallback? onShowUpdateDetails;
  final void Function(String sessionId)? onOpenSession;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationCenterProvider>();
    final items = provider.notifications;

    return Material(
      color: const Color(0xFF1E1E1E),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (items.isNotEmpty)
                    TextButton(
                      onPressed: provider.clearAll,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary),
                      child:
                          const Text('Clear all', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            if (items.isEmpty)
              _buildEmptyState()
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) => _NotificationTile(
                    item: items[i],
                    onShowUpdateDetails: onShowUpdateDetails,
                    onOpenSession: onOpenSession,
                    onClose: onClose,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.cardHover,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications,
                size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 14),
          const Text(
            'No notifications',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onShowUpdateDetails,
    required this.onOpenSession,
    required this.onClose,
  });

  final AppNotification item;
  final VoidCallback? onShowUpdateDetails;
  final void Function(String sessionId)? onOpenSession;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDisconnect = item.type == AppNotificationType.sessionDisconnect;

    return InkWell(
      onTap: isDisconnect && item.sessionId != null
          ? () {
              onClose();
              onOpenSession?.call(item.sessionId!);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isDisconnect ? Icons.link_off : Icons.system_update_alt,
              size: 15,
              color: isDisconnect ? AppColors.orange : AppColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12.5)),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11.5),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    relativeTime(item.timestamp),
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 10.5),
                  ),
                  if (item.type == AppNotificationType.update) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          child: FilledButton(
                            onPressed: () {
                              onClose();
                              context
                                  .read<UpdateProvider>()
                                  .downloadAndInstall();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              textStyle: const TextStyle(fontSize: 11.5),
                            ),
                            child: const Text('Update'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 24,
                          child: TextButton(
                            onPressed: () {
                              onClose();
                              onShowUpdateDetails?.call();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              textStyle: const TextStyle(fontSize: 11.5),
                            ),
                            child: const Text('Details'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "just now", "5m ago", "3h ago", "2d ago".
@visibleForTesting
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/notification_bell_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/notification_bell.dart app/test/widgets/notification_bell_test.dart
git commit -m "feat(notifications): bell button with badge and anchored popover panel"
```

---

### Task 4: Mount in _TopTabBar + wire sources in main.dart

**Files:**
- Modify: `app/lib/screens/main_screen.dart` (`_TopTabBar` ~line 1047, its instantiation ~line 521, `UpdateBanner` ~line 550)
- Modify: `app/lib/main.dart` (provider creation ~line 238, MultiProvider ~line 345, dispose ~line 294)

There is no new unit-testable logic in this task (pure wiring); verification is `flutter analyze` + the full test suite + a manual smoke run.

- [ ] **Step 1: Extract `_showUpdateDetails` in MainScreen**

In `app/lib/screens/main_screen.dart`, the `UpdateBanner(onShowDetails: ...)` closure (line 550) duplicates navigation the bell also needs. Add a method to `_MainScreenState`:

```dart
  void _showUpdateDetails() => setState(() {
        _activePluginId = null;
        _activeScriptPanel = null;
        _nav = NavSection.settings;
        _viewingTerminal = false;
        _showAiChat = false;
      });
```

Replace the banner wiring with:

```dart
          UpdateBanner(onShowDetails: _showUpdateDetails),
```

- [ ] **Step 2: Add bell to `_TopTabBar`**

Add the import at the top of `main_screen.dart`:

```dart
import 'package:yourssh/widgets/notification_bell.dart';
```

In `_TopTabBar` (line 1047), add two fields and constructor params:

```dart
  final VoidCallback onShowUpdateDetails;
  final ValueChanged<String> onOpenSession;
```

```dart
  const _TopTabBar({
    required this.sessions,
    required this.active,
    required this.nav,
    required this.viewingTerminal,
    required this.onNavSelect,
    required this.onSessionTap,
    required this.onAddSession,
    required this.onAddLocalSession,
    required this.onShowUpdateDetails,
    required this.onOpenSession,
  });
```

In its `build`, after the `_AddTabBtn` row entry (line 1118):

```dart
          _AddTabBtn(onNewSsh: onAddSession, onNewLocal: onAddLocalSession),
          NotificationBellBtn(
            onShowUpdateDetails: onShowUpdateDetails,
            onOpenSession: onOpenSession,
          ),
```

In the `_TopTabBar(...)` instantiation in `_MainScreenState.build` (line 521), add:

```dart
            onShowUpdateDetails: _showUpdateDetails,
            onOpenSession: (sessionId) {
              final sp = context.read<SessionProvider>();
              if (sp.sessions.any((s) => s.id == sessionId)) {
                sp.setActive(sessionId);
                setState(() => _viewingTerminal = true);
              }
            },
```

- [ ] **Step 3: Wire sources in main.dart**

Add imports to `app/lib/main.dart`:

```dart
import 'package:yourssh/models/app_notification.dart';
import 'package:yourssh/providers/notification_center_provider.dart';
```

Add fields to the app state class (next to `late final UpdateProvider _updateProvider;`, line 126):

```dart
  late final NotificationCenterProvider _notificationCenter;
  String? _lastUpdateNotifVersion;
```

In `initState`, right after `_updateProvider` is created (line 238):

```dart
    _notificationCenter = NotificationCenterProvider();
    _updateProvider.addListener(_pushUpdateNotification);
    _sessionProvider.onSessionDropped = (session, reason) {
      _notificationCenter.add(AppNotification(
        type: AppNotificationType.sessionDisconnect,
        title: 'Session disconnected: ${session.title}',
        body: reason,
        dedupeKey: 'disconnect:${session.id}',
        sessionId: session.id,
      ));
    };
```

Add the listener method (next to `_syncNotificationSetting`, line 272):

```dart
  /// Mirrors "update available" into the notification center exactly once
  /// per version (UpdateProvider notifies repeatedly while available).
  void _pushUpdateNotification() {
    if (_updateProvider.status != UpdateStatus.available) return;
    final v = _updateProvider.latestRelease?.version;
    if (v == null || v == _lastUpdateNotifVersion) return;
    _lastUpdateNotifVersion = v;
    _notificationCenter.add(AppNotification(
      type: AppNotificationType.update,
      title: 'New version v$v available',
      dedupeKey: 'update:$v',
    ));
  }
```

In the `MultiProvider` providers list (next to `_updateProvider`, line 345):

```dart
        ChangeNotifierProvider.value(value: _notificationCenter),
```

In `dispose()` (line 294), before `_sessionProvider.dispose()`:

```dart
    _updateProvider.removeListener(_pushUpdateNotification);
    _notificationCenter.dispose();
```

- [ ] **Step 4: Analyze + full test suite**

Run: `cd app && flutter analyze && flutter test`
Expected: `No issues found!` and all tests PASS.

- [ ] **Step 5: Update CHANGELOG**

In `CHANGELOG.md`, under the `[Unreleased]` section's `### Added` heading (create the heading if missing), add:

```markdown
- Notification bell in the top tab bar with unread badge and popover panel: update-available and session-disconnect notifications, mark-read on open, clear all.
```

- [ ] **Step 6: Commit**

```bash
git add app/lib/screens/main_screen.dart app/lib/main.dart CHANGELOG.md
git commit -m "feat(notifications): mount bell in top tab bar and wire update/disconnect sources"
```

- [ ] **Step 7: Manual smoke check (optional but recommended)**

Run: `cd app && flutter run -d macos`
- Bell renders right of `+`; no badge initially.
- Click bell → empty-state panel ("No notifications"); click outside → closes.
- Connect a host with a wrong port (auto-reconnect off in Settings) → badge `1`; panel shows the disconnect item; clicking it activates that tab.
