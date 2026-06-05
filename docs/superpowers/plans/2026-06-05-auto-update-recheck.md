# Auto Update Re-check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The notification bell picks up new releases on its own while the app stays running (periodic timer + window-focus re-check), instead of only on a fresh launch.

**Architecture:** `UpdateProvider` gains a `Timer.periodic` (default 6 h, injectable for tests) that calls the existing `checkForUpdates()`; `main.dart` starts it and also re-checks on `onWindowFocus()`. The existing 24 h debounce inside `checkForUpdates()` caps GitHub API calls at ~once/day; the existing `_pushUpdateNotification` listener already mirrors `available` into the bell, so no bell changes.

**Tech Stack:** Flutter/Dart, `dart:async` Timer, `fake_async` (already a flutter_test transitive dep) for deterministic timer tests.

**Spec:** `docs/superpowers/specs/2026-06-05-auto-update-recheck-design.md`

---

### Task 1: Periodic timer in `UpdateProvider` (TDD)

**Files:**
- Modify: `app/lib/providers/update_provider.dart`
- Test: `app/test/providers/update_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `app/test/providers/update_provider_test.dart`. Add the import at the top of the file (after the existing `flutter_test` import):

```dart
import 'package:fake_async/fake_async.dart';
```

Append this group inside `main()`, after the `dismiss hides the banner...` test:

```dart
  group('periodic checks', () {
    test('timer fires an auto check and stays debounced within 24h', () {
      fakeAsync((async) {
        var clock = DateTime.utc(2026, 6, 3, 12);
        final svc = _FakeService(_rel('v0.2.0'));
        final p = UpdateProvider(
          svc,
          currentVersion: '0.1.18',
          now: () => clock,
          checkInterval: const Duration(hours: 6),
        );
        p.startPeriodicChecks();

        // First tick: no prior check recorded -> fetches.
        async.elapse(const Duration(hours: 6));
        expect(svc.fetchCount, 1);

        // Two more ticks inside the 24h debounce window -> no fetch.
        async.elapse(const Duration(hours: 12));
        expect(svc.fetchCount, 1);

        // Move the injected clock past the debounce window; next tick fetches.
        clock = clock.add(const Duration(hours: 25));
        async.elapse(const Duration(hours: 6));
        expect(svc.fetchCount, 2);

        p.dispose();
      });
    });

    test('startPeriodicChecks is idempotent (replaces the old timer)', () {
      fakeAsync((async) {
        final svc = _FakeService(_rel('v0.2.0'));
        final p = UpdateProvider(
          svc,
          currentVersion: '0.1.18',
          checkInterval: const Duration(hours: 6),
        );
        p.startPeriodicChecks();
        p.startPeriodicChecks();
        expect(async.pendingTimers.length, 1);
        p.dispose();
      });
    });

    test('dispose cancels the timer', () {
      fakeAsync((async) {
        final svc = _FakeService(_rel('v0.2.0'));
        final p = UpdateProvider(
          svc,
          currentVersion: '0.1.18',
          checkInterval: const Duration(hours: 6),
        );
        p.startPeriodicChecks();
        p.dispose();
        async.elapse(const Duration(hours: 12));
        expect(svc.fetchCount, 0);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/update_provider_test.dart`
Expected: compile error — `No named parameter with the name 'checkInterval'` (and `startPeriodicChecks` undefined).

- [ ] **Step 3: Implement the timer in `UpdateProvider`**

In `app/lib/providers/update_provider.dart`:

Add the import at the top:

```dart
import 'dart:async';
```

Change the constructor and add the field (the class doc comment gains the re-check mention):

```dart
/// Drives the in-app update flow: debounced launch check, periodic/focus
/// re-checks, manual check, download, and install hand-off. Surfaces state
/// to the banner and Settings.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider(
    this._service, {
    required this.currentVersion,
    DateTime Function()? now,
    this.checkInterval = const Duration(hours: 6),
  }) : _now = now ?? DateTime.now;
```

Add after the `_now` field declaration:

```dart
  /// How often the periodic re-check ticks. Ticks are still debounced to
  /// 24h by [checkForUpdates], so GitHub is hit at most ~once per day.
  final Duration checkInterval;

  Timer? _periodicTimer;
```

Add the methods (after `checkForUpdates`):

```dart
  /// Re-checks for updates while the app stays running, so a release
  /// published after launch still reaches the notification bell. Safe to
  /// call more than once; the previous timer is replaced.
  void startPeriodicChecks() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(checkInterval, (_) => checkForUpdates());
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/update_provider_test.dart`
Expected: all tests PASS (5 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/update_provider.dart app/test/providers/update_provider_test.dart
git commit -m "feat(update): periodic update re-check timer in UpdateProvider"
```

---

### Task 2: Wire timer start + focus re-check in `main.dart`

**Files:**
- Modify: `app/lib/main.dart:266-269` (start timer) and `app/lib/main.dart:331-341` (`onWindowFocus`)

- [ ] **Step 1: Start the periodic timer after the launch check**

In `app/lib/main.dart`, change:

```dart
    _updateProvider = UpdateProvider(_updateService, currentVersion: kAppVersion);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateProvider.checkForUpdates();
    });
```

to:

```dart
    _updateProvider = UpdateProvider(_updateService, currentVersion: kAppVersion);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateProvider.checkForUpdates();
    });
    _updateProvider.startPeriodicChecks();
```

(`_updateProvider.dispose()` is already called in this widget's `dispose()` at `main.dart:376`, which now cancels the timer — no teardown change needed.)

- [ ] **Step 2: Re-check on window focus**

In `onWindowFocus()` (`app/lib/main.dart:331`), change:

```dart
  @override
  void onWindowFocus() {
    NotificationService.instance.onWindowFocus();
```

to:

```dart
  @override
  void onWindowFocus() {
    NotificationService.instance.onWindowFocus();
    // Auto re-check on refocus (still debounced to 24h internally).
    _updateProvider.checkForUpdates();
```

- [ ] **Step 3: Analyze and run the full test suite**

Run: `cd app && flutter analyze`
Expected: `No issues found!`

Run: `cd app && flutter test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(update): start periodic update checks and re-check on window focus"
```

---

### Task 3: Update CLAUDE.md provider description

**Files:**
- Modify: `CLAUDE.md` (the `UpdateProvider` bullet under **Providers**)

- [ ] **Step 1: Edit the `UpdateProvider` bullet**

Change:

```markdown
- `UpdateProvider` — in-app update flow: launch check (debounced 24h via `last_update_check` in `SharedPreferences`) + manual check, semver compare, download progress, and install hand-off; `showBanner` derived from `status == available && version != dismissedVersion`; `dismiss()` persists per-version; surfaces state to `UpdateBanner` and the Settings Updates section
```

to:

```markdown
- `UpdateProvider` — in-app update flow: launch check + periodic re-check (`startPeriodicChecks()`, `Timer.periodic` every `checkInterval`, default 6h) + window-focus re-check (wired in `main.dart.onWindowFocus`) + manual check — auto checks all debounced 24h via `last_update_check` in `SharedPreferences`; semver compare, download progress, and install hand-off; `showBanner` derived from `status == available && version != dismissedVersion`; `dismiss()` persists per-version; surfaces state to `UpdateBanner` and the Settings Updates section
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: UpdateProvider periodic + focus re-check in CLAUDE.md"
```
