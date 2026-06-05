# Auto Update Re-check While the App Is Running — Design

**Date:** 2026-06-05
**Status:** Approved

## Problem

`UpdateProvider.checkForUpdates()` runs exactly once, at launch
(`main.dart` post-frame callback), debounced to 24 h via the
`last_update_check` pref. yourssh is a long-running desktop app: if the
user keeps it open for days (or relaunches within the debounce window),
a release published after the last check never reaches the notification
bell until the app is restarted. The bell only lights up "automatically"
in the narrow case of a fresh launch more than 24 h after the previous
check — otherwise the user has to press the manual check in Settings.

## Goal

The bell notifies about a new version on its own while the app stays
running, with no new API-call pressure on GitHub.

## Design

Two small changes; the existing bell wiring
(`_pushUpdateNotification` listener, per-version dedupe) is untouched.

### 1. Periodic timer in `UpdateProvider`

- New `startPeriodicChecks()` creates a `Timer.periodic` that calls
  `checkForUpdates()` (auto, `manual: false`).
- Interval is a constructor parameter (`checkInterval`, default 6 h) so
  tests can inject a short one.
- Timer is cancelled in `dispose()`; calling `startPeriodicChecks()`
  twice must not leak a second timer.
- `main.dart` calls `startPeriodicChecks()` right after the existing
  launch check.

### 2. Check on window focus

- `onWindowFocus()` in `main.dart` (where the sync pull already runs)
  additionally calls `_updateProvider.checkForUpdates()`.

## Resulting behavior

- The 24 h debounce stays as-is, so regardless of 6 h timer ticks or
  repeated focus events, GitHub is hit at most ~once per day.
- App parked in the background for days: the timer still picks up a new
  release → bell lights up.
- User returns to the app after > 24 h away: the focus check catches it
  immediately.
- No duplicate notifications: `_lastUpdateNotifVersion` in `main.dart`
  and `AppNotification.dedupeKey` (`update:<version>`) already dedupe
  per version.

## Error handling

`checkForUpdates` already maps network failures to `UpdateStatus.error`
without surfacing anything in the bell — a failed background check is
silent, which is the desired behavior.

## Testing

Unit tests on `UpdateProvider` (fake clock is already injectable via
`now`; inject a short `checkInterval`):

- Timer tick triggers a check, and the 24 h debounce still suppresses
  ticks that come too soon.
- `dispose()` cancels the timer (no check fires afterwards).
- `startPeriodicChecks()` is idempotent.

Focus-triggered check is a one-line call into the same already-tested
method; covered by the debounce tests above.
