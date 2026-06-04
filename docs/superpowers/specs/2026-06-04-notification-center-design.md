# Notification Center (bell icon in top tab bar) — Design

**Date:** 2026-06-04
**Status:** Approved

## Goal

Add a notification bell icon next to the `+` button in the top tab bar. Clicking it opens an
anchored popover listing in-app notifications (app update available, unexpected session
disconnects), with an unread-count badge and a "No notifications" empty state.

The existing `UpdateBanner` is **kept unchanged** — the bell adds a second, persistent surface
for the same update information (user decision).

## Scope (v1)

- Notification sources: **update available** and **session disconnect** only.
- In-memory store — notifications do not survive an app restart (the 24h-debounced update
  check recreates the update item on next launch).
- Badge counts unread items; opening the panel marks all as read.
- "Clear all" button; no per-item dismiss UI in v1 (provider supports `remove(id)` for future use).

## Components

### 1. Model — `app/lib/models/app_notification.dart`

```dart
enum AppNotificationType { update, sessionDisconnect }

class AppNotification {
  final String id;            // unique, timestamp-derived
  final AppNotificationType type;
  final String title;         // e.g. "New version v0.1.25 available"
  final String? body;         // error message / short detail
  final DateTime timestamp;
  final String? dedupeKey;    // "update:v0.1.25", "disconnect:<sessionId>"
  final String? sessionId;    // sessionDisconnect only — enables jump-to-tab
  bool read;
}
```

### 2. Provider — `app/lib/providers/notification_center_provider.dart`

`NotificationCenterProvider extends ChangeNotifier`:

- `List<AppNotification> get notifications` — newest first.
- `int get unreadCount`.
- `void add(AppNotification n)` — if an existing item has the same non-null `dedupeKey`,
  replace it in place (new item is unread); otherwise prepend. List capped at 50 items
  (oldest dropped).
- `void markAllRead()` — sets `read = true` on all items.
- `void clearAll()`.
- `void remove(String id)`.

### 3. Wiring — `app/lib/main.dart`

- **Update:** add a listener on `UpdateProvider`. When `status == UpdateStatus.available`
  and `latestRelease != null`, push a notification with `dedupeKey: 'update:<version>'`.
  Independent of the banner's dismissed state — dismissing the banner does not remove the
  bell item.
- **Disconnect:** new callback on `SessionProvider`:
  `void Function(SshSession session, String? reason)? onSessionDropped`, fired at the
  two terminal-drop points in `_doConnect`:
  - shell closed without auto-reconnect → `SessionStatus.disconnected`
    (`session_provider.dart:154`)
  - reconnect attempts exhausted / connect failure → `SessionStatus.error`
    (`session_provider.dart:166`), with the error message as `reason`.

  Wired in `main.dart` to push a notification with `dedupeKey: 'disconnect:<sessionId>'`.

  **Known caveat:** a graceful `exit` typed by the user also lands on the
  shell-closed path; the layer cannot distinguish it from a network drop, so v1 notifies
  on both. The session tab shows the same disconnected state, so the information is
  consistent. Revisit if noisy.

### 4. UI — `app/lib/widgets/notification_bell.dart`

`NotificationBellBtn` — stateful widget placed after `_AddTabBtn` at the right end of
`_TopTabBar` (`app/lib/screens/main_screen.dart`):

- Bell icon (`Icons.notifications_none`, 16px), hover colors matching `_AddTabBtn`
  (`#555555` → `#AAAAAA`).
- Red badge (top-right of icon) with `unreadCount`; renders `9+` above 9; hidden at 0.
- Click toggles an anchored popover via `OverlayPortal` + `CompositedTransformTarget`/
  `Follower`, dismissed by `TapRegion` outside-tap. Panel: ~320px wide, right-aligned
  under the bell, `#1E1E1E` background, `AppColors.border` border, 12px radius.
- Opening the panel calls `markAllRead()`.
- Header row: "Notifications" label + **Clear all** text button (only when non-empty).
- Item rows: type icon, title, optional body (max 2 lines), relative time ("2m ago").
  - `update` item: **Update** button → `UpdateProvider.downloadAndInstall()`;
    **Details** button → navigate to Settings (callback `onShowUpdateDetails` injected
    from `MainScreen`, same navigation as `UpdateBanner.onShowDetails`).
  - `sessionDisconnect` item: tapping the row activates that session tab if it still
    exists (callback `onOpenSession(sessionId)` injected from `MainScreen`); no-op
    otherwise.
- Empty state (per mockup): centered bell icon inside a rounded square + "No notifications".

### 5. Registration

`NotificationCenterProvider` is created in `main.dart` alongside the other long-lived
providers and exposed through the existing `MultiProvider`.

## Error handling

Everything is in-memory and synchronous; no I/O. Callbacks wired in `main.dart` are
null-safe (`?.call`) so the provider works standalone in tests.

## Testing

- **Provider unit tests** (`app/test/providers/notification_center_provider_test.dart`):
  add/prepend order, dedupe-replace keeps single item, unread count, `markAllRead`,
  `clearAll`, `remove`, 50-item cap.
- **Widget tests** (`app/test/widgets/notification_bell_test.dart`): badge hidden at 0 /
  shows count / `9+`; tap opens panel; empty state text; update item shows Update +
  Details buttons and fires callbacks; opening panel clears badge.

## Out of scope (future)

- Persistence across restarts.
- Additional sources (sync errors, SFTP transfer completion).
- Per-item dismiss UI, notification settings, OS-toast mirroring.
