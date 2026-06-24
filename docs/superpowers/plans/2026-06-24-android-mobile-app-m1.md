# Android Mobile App — Milestone 1 (Target + Platform Branch) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Android target to the existing `app/` Flutter project and make a debug APK launch into an empty mobile shell, without regressing the desktop builds.

**Architecture:** The whole widget tree branches at the app root: `main()` mounts the existing desktop `YourSSHApp` on desktop and a new `YourSSHMobileApp` on Android. Because the trees are fully separate, desktop-only plugin calls inside desktop widgets (`window_manager`, `hotkey_manager` in `main_screen.dart`, `terminal_view.dart`, etc.) never execute on mobile — so M1 only needs to gate the *shared* bootstrap in `main()` and provide a minimal mobile root. The fuller `platform/` abstraction classes from the spec (`WindowChrome`, `GlobalHotkeys`, `AppNotifier`, `LocalShell`) are introduced later, when a mobile screen actually needs that capability; M1 ships only `runtime_platform.dart` (platform detection).

**Tech Stack:** Flutter, Dart, `provider`, existing `AppColors` theme. No new dependencies in M1.

## Global Constraints

- Project name (Dart package): `yourssh` — imports are `package:yourssh/...`.
- Android `applicationId` / `--org`: `com.thangnm` → `com.thangnm.yourssh` (matches macOS `com.thangnm.yourssh`).
- App is **dark-only** (`ThemeMode.dark`); colors come from `app/lib/theme/app_theme.dart` (`AppColors`). Never introduce a light theme.
- Desktop builds (macOS/Windows/Linux) MUST keep building; `flutter analyze` MUST stay clean across the repo.
- No Claude attribution anywhere (commits, comments, docs).
- Commit after each task. Work on branch `feat/android-mobile-app` (already checked out).
- **Prerequisite (one-time, user-run):** Android SDK licenses must be accepted before an APK can build — `flutter doctor --android-licenses`. If unaccepted, code/test tasks still complete; only the final build/run step is blocked.

---

### Task 1: Generate the Android target

**Files:**
- Create: `app/android/**` (generated)
- Modify: none by hand in this task

**Interfaces:**
- Consumes: nothing
- Produces: an `app/android/` Gradle project with `applicationId "com.thangnm.yourssh"`

- [ ] **Step 1: Generate the android platform files**

Run (from repo root):
```bash
cd app && flutter create --platforms=android --org com.thangnm --project-name yourssh .
```
Expected: creates `app/android/` and prints "All done!". Existing `lib/`, `macos/`, `windows/`, `linux/`, `pubspec.yaml` are left intact (flutter create only adds the missing platform).

- [ ] **Step 2: Verify the target was added and desktop dirs untouched**

Run:
```bash
cd app && ls android/app/src/main/AndroidManifest.xml && grep -r 'applicationId' android/app/build.gradle*
```
Expected: the manifest path prints, and `applicationId = "com.thangnm.yourssh"` (or `applicationId "com.thangnm.yourssh"`) appears.

- [ ] **Step 3: Verify desktop still analyzes clean**

Run:
```bash
cd app && flutter pub get && flutter analyze
```
Expected: `No issues found!` (or unchanged from before — no NEW issues).

- [ ] **Step 4: Commit**

```bash
cd /Users/thangnguyen/Projects/Personal/yourssh
git add app/android app/pubspec.lock app/.metadata 2>/dev/null; git add -A app/android
git commit -m "build(android): add Android target via flutter create"
```

---

### Task 2: Platform detection helper (`runtime_platform.dart`)

**Files:**
- Create: `app/lib/platform/runtime_platform.dart`
- Test: `app/test/platform/runtime_platform_test.dart`

**Interfaces:**
- Consumes: `package:flutter/foundation.dart` (`defaultTargetPlatform`, `TargetPlatform`)
- Produces: `bool get isMobilePlatform` — true on Android/iOS, false on desktop. Used by `main()` (Task 4).

- [ ] **Step 1: Write the failing test**

Create `app/test/platform/runtime_platform_test.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/platform/runtime_platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('isMobilePlatform is true on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isMobilePlatform, isTrue);
  });

  test('isMobilePlatform is true on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isMobilePlatform, isTrue);
  });

  test('isMobilePlatform is false on macOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isMobilePlatform, isFalse);
  });

  test('isMobilePlatform is false on Windows and Linux', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(isMobilePlatform, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(isMobilePlatform, isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd app && flutter test test/platform/runtime_platform_test.dart
```
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh' ... runtime_platform.dart` / target of URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/platform/runtime_platform.dart`:
```dart
import 'package:flutter/foundation.dart';

/// True when running on a mobile platform (Android/iOS).
///
/// Drives the desktop-vs-mobile branch in `main()` and gates the desktop-only
/// bootstrap (window_manager / hotkey_manager / local_notifier). Uses
/// [defaultTargetPlatform] (not `dart:io` `Platform`) so it is overridable in
/// widget/unit tests via `debugDefaultTargetPlatformOverride`.
bool get isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd app && flutter test test/platform/runtime_platform_test.dart
```
Expected: PASS — all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/platform/runtime_platform.dart app/test/platform/runtime_platform_test.dart
git commit -m "feat(mobile): add isMobilePlatform runtime detection"
```

---

### Task 3: Minimal mobile root (`YourSSHMobileApp` + bottom-nav shell)

**Files:**
- Create: `app/lib/mobile/mobile_app.dart`
- Create: `app/lib/mobile/screens/mobile_home_shell.dart`
- Test: `app/test/mobile/mobile_home_shell_test.dart`

**Interfaces:**
- Consumes: `AppColors` from `package:yourssh/theme/app_theme.dart`
- Produces:
  - `class YourSSHMobileApp extends StatelessWidget` — the mobile `MaterialApp` root, mounted by `main()` (Task 4).
  - `class MobileHomeShell extends StatefulWidget` — a `Scaffold` with a 4-destination `NavigationBar` (Hosts / Sessions / SFTP / Settings). Each destination shows a centered placeholder for M1.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_home_shell_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';

void main() {
  testWidgets('shows four destinations and Hosts first', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MobileHomeShell()));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Hosts'), findsWidgets);
    expect(find.text('Sessions'), findsWidgets);
    expect(find.text('SFTP'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Hosts tab body is shown first.
    expect(find.text('Hosts — coming soon'), findsOneWidget);
  });

  testWidgets('tapping a destination switches the body', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MobileHomeShell()));

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Settings — coming soon'), findsOneWidget);
    expect(find.text('Hosts — coming soon'), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd app && flutter test test/mobile/mobile_home_shell_test.dart
```
Expected: FAIL — target of URI doesn't exist (`mobile_home_shell.dart`).

- [ ] **Step 3: Write `MobileHomeShell`**

Create `app/lib/mobile/screens/mobile_home_shell.dart`:
```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Bottom-navigation shell for the Android app. M1 renders placeholder bodies;
/// each destination is filled in over later milestones (M2 terminal, M3 sync,
/// M4 SFTP/snippets, M5 settings/app-lock).
class MobileHomeShell extends StatefulWidget {
  const MobileHomeShell({super.key});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  int _index = 0;

  static const _labels = ['Hosts', 'Sessions', 'SFTP', 'Settings'];
  static const _icons = [
    Icons.dns_outlined,
    Icons.terminal_outlined,
    Icons.folder_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Text(
            '${_labels[_index]} — coming soon',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write `YourSSHMobileApp`**

Create `app/lib/mobile/mobile_app.dart`:
```dart
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'screens/mobile_home_shell.dart';

/// Root widget for the Android build. Dark-only, mirrors the desktop theme
/// surface. Providers/services are wired here starting in M2.
class YourSSHMobileApp extends StatelessWidget {
  const YourSSHMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YourSSH',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          surface: AppColors.bg,
          primary: AppColors.green,
        ),
      ),
      home: const MobileHomeShell(),
    );
  }
}
```

> NOTE: confirm the exact `AppColors` member names (`bg`, `green`, `textSecondary`) by opening `app/lib/theme/app_theme.dart`; if a name differs (e.g. `accent` vs `green`), use the real one. The test in Step 1 does not depend on colors.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
cd app && flutter test test/mobile/mobile_home_shell_test.dart
```
Expected: PASS — both tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/mobile app/test/mobile
git commit -m "feat(mobile): minimal mobile app shell with bottom nav"
```

---

### Task 4: Branch `main()` by platform and gate desktop-only bootstrap

**Files:**
- Modify: `app/lib/main.dart` (the `main()` function, lines ~110–127; and the `runApp` call)

**Interfaces:**
- Consumes: `isMobilePlatform` (Task 2), `YourSSHMobileApp` (Task 3)
- Produces: a `main()` that runs the desktop bootstrap only on desktop and mounts the right root per platform.

- [ ] **Step 1: Add imports to `main.dart`**

At the top of `app/lib/main.dart`, add (next to the existing imports):
```dart
import 'platform/runtime_platform.dart';
import 'mobile/mobile_app.dart';
```

- [ ] **Step 2: Gate the desktop-only init and branch `runApp`**

Replace the body of `main()` (currently):
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kAppVersion = (await PackageInfo.fromPlatform()).version;
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    title: 'YourSSH',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await hotKeyManager.unregisterAll();
  await NotificationService.init();
  runApp(const YourSSHApp());
}
```
with:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kAppVersion = (await PackageInfo.fromPlatform()).version;

  if (isMobilePlatform) {
    // Mobile: skip all desktop-only bootstrap (window_manager, hotkey_manager,
    // local_notifier have no Android implementation and would throw).
    runApp(const YourSSHMobileApp());
    return;
  }

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(800, 600),
    center: true,
    title: 'YourSSH',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await hotKeyManager.unregisterAll();
  await NotificationService.init();
  runApp(const YourSSHApp());
}
```

- [ ] **Step 3: Verify analyze is clean**

Run:
```bash
cd app && flutter analyze
```
Expected: `No issues found!` (no unused-import warnings; both new imports are referenced).

- [ ] **Step 4: Verify the full test suite still passes (desktop regression guard)**

Run:
```bash
cd app && flutter test
```
Expected: all tests pass (same as before the branch — `main.dart` changes don't touch desktop widget behavior).

- [ ] **Step 5: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat(mobile): branch main() to mobile app on Android"
```

---

### Task 5: Build & run the Android APK (spike — confirms desktop plugins don't break Gradle)

**Files:** none (verification only)

**Interfaces:**
- Consumes: everything above
- Produces: a launchable debug APK; confirmation that `window_manager`, `hotkey_manager`, `local_notifier`, `flutter_pty`, `sqlite3_flutter_libs`, `webview_flutter` do not break the Android Gradle build.

- [ ] **Step 1: (User, one-time) accept Android SDK licenses**

If not already done, the user runs in their session:
```
! flutter doctor --android-licenses
```
(Accept each prompt.) Then confirm `flutter doctor` shows the Android toolchain without `[!]` for licenses.

- [ ] **Step 2: Build the debug APK**

Run:
```bash
cd app && flutter build apk --debug
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. If Gradle fails on a desktop-only plugin, that is the spike's finding — capture the error and address it (most likely none, since those plugins declare no Android platform; `flutter_pty` fork declares Android and should build).

- [ ] **Step 3: Run on a device/emulator (if available)**

Run:
```bash
cd app && flutter devices
```
If an Android device/emulator is listed:
```bash
cd app && flutter run -d <android-device-id>
```
Expected: the app launches and shows the bottom nav with "Hosts — coming soon"; tapping destinations switches the placeholder. No crash on launch (confirms the desktop-only init was correctly skipped).

- [ ] **Step 4: Desktop regression check**

Run:
```bash
cd app && flutter build macos --debug
```
Expected: builds successfully (desktop bootstrap unchanged).

- [ ] **Step 5: Commit any Gradle/config fixes discovered**

Only if Step 2/3 required changes (e.g. `minSdkVersion` bump, NDK setting). Otherwise nothing to commit.

```bash
git add -A app/android && git commit -m "build(android): <describe fix>"
```

---

## Self-Review

**Spec coverage (M1 portion of the spec):**
- "New `android/` target (`flutter create --platforms=android .`)" → Task 1. ✓
- "branch at the app root by platform" (`main.dart`) → Task 4. ✓
- "`platform/` … platform detection" → Task 2 (`runtime_platform.dart`); fuller abstraction classes deliberately deferred (documented in Architecture). ✓
- "empty `MobileApp` shell" + bottom nav (Hosts/Sessions/SFTP/Settings) → Task 3. ✓
- Spike 1 ("build a debug APK … confirm desktop plugins don't break Gradle") → Task 5. ✓
- "desktop builds unchanged; `flutter analyze` clean" → Tasks 1/4 steps + Task 5 Step 4. ✓

**Placeholder scan:** No "TBD/TODO/handle edge cases" steps; every code step shows full code. The one NOTE (AppColors member names) is a verify-the-real-name instruction with a concrete fallback, not a placeholder.

**Type consistency:** `isMobilePlatform` (Task 2) used verbatim in Task 4. `YourSSHMobileApp` (Task 3 `mobile_app.dart`) imported and constructed in Task 4. `MobileHomeShell` (Task 3) referenced only within `mobile_app.dart`. Names consistent.

## Next milestones (separate plans, written after M1 lands)

- **M2** — Hosts list + detail + connect; mobile `TerminalView`; accessory key bar (sticky Ctrl/Alt); multi-session strip; pinch-zoom. Introduces the shared provider bootstrap (extract from `_YourSSHAppState`).
- **M3** — Cloud + P2P QR sync import.
- **M4** — Single-panel SFTP (SAF transfers) + snippets/history insert.
- **M5** — Biometric app-lock (`local_auth`), TOFU dialog, appearance settings, release APK signing.
