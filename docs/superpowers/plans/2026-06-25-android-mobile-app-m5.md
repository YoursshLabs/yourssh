# Android Mobile App — Milestone 5 (Security + Polish, v1 finale) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Android v1 — biometric app-lock, the TOFU host-key-mismatch dialog, terminal appearance settings, and release APK signing.

**Architecture:** App-lock is a `AppLockGate` wrapping the home, with an injectable authenticator (real one = `local_auth`) so the lock state machine is unit-testable without device biometrics. The TOFU mismatch dialog is a small watcher on `KnownHostsProvider.pendingChallenge` (mobile equivalent of the desktop `MainScreen` watcher). Appearance reuses the shared `TerminalAppearanceControls` + `resolveTerminalAppearance` + `terminalThemeByName`. Release signing follows the standard Flutter `key.properties` pattern (gitignored; falls back to debug signing when absent).

**Tech Stack:** Flutter, `provider`, `local_auth` (new), existing `KnownHostsProvider`/`SettingsProvider`/`xterm`.

## Global Constraints

- Dart package `yourssh`; dark-only (`AppColors`); reuse existing classes; don't modify desktop bootstrap/widgets.
- App-lock default **on**; toggle persisted (pref key `app_lock_enabled`); never lock desktop (gate is mobile-only).
- TOFU: first-connect still auto-trusts; this milestone only adds the **mismatch** dialog.
- Desktop builds + full `flutter test` + `flutter analyze` MUST stay green.
- `local_auth` reintroduced **for mobile**; same accepted bundle tradeoff as noted in the spec (single shared pubspec).
- No Claude attribution. Commit after each task. Branch `feat/android-mobile-app`.

## Key existing APIs (verified)

- `KnownHostsProvider.pendingChallenge` → `HostKeyChallenge?` (`host`, `port`, `keyType`, `oldFingerprint`, `newFingerprint`; `accept()`, `reject()` from `TofuChallenge`). The provider `notifyListeners()` when it changes.
- `resolveTerminalAppearance({required Host? host, required String globalTheme, required String globalFont, required double globalFontSize})` → `TerminalAppearance{themeName, fontFamily, fontSize}`.
- `terminalThemeByName(String)` → xterm `TerminalTheme`. `SettingsProvider.terminalTheme` / `.terminalFont` / `.fontSize`.
- `TerminalAppearanceControls({required AppearanceControlsLayout layout})` — standalone, reads/writes `SettingsProvider`.
- `TerminalView(terminal, {theme, textStyle})`; `TerminalStyle(fontSize:, fontFamily:)`.

---

## Phase M5.1 — Biometric app-lock

### Task 1: Add local_auth dependency

**Files:** Modify `app/pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `app/pubspec.yaml` dependencies add:
```yaml
  local_auth: ^2.3.0
```
Run: `cd app && flutter pub get`
Expected: resolves. (If `^2.3.0` won't resolve, `flutter pub add local_auth` and accept the compatible version.)

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze lib/mobile`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "build(mobile): add local_auth for app-lock"
```

---

### Task 2: App-lock gate

**Files:**
- Create: `app/lib/mobile/security/app_lock_gate.dart`
- Modify: `app/lib/mobile/mobile_app.dart` (wrap home in `AppLockGate`)
- Test: `app/test/mobile/app_lock_gate_test.dart`

**Interfaces:**
- Produces: `class AppLockGate extends StatefulWidget` with `child`, optional `Future<bool> Function()? authenticator` (default `local_auth`), optional `bool? enabledOverride` (tests), optional `Future<bool> Function()? readEnabled`. Locked → shows a lock screen with an Unlock button; unlocked → shows `child`. Re-locks on resume-from-background when enabled.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/app_lock_gate_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';

const _childKey = Key('locked-child');

Future<void> _pump(WidgetTester tester,
    {required bool enabled, required Future<bool> Function() auth}) async {
  await tester.pumpWidget(MaterialApp(
    home: AppLockGate(
      enabledOverride: enabled,
      authenticator: auth,
      child: const Scaffold(body: SizedBox(key: _childKey)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('disabled shows child immediately', (tester) async {
    await _pump(tester, enabled: false, auth: () async => false);
    expect(find.byKey(_childKey), findsOneWidget);
  });

  testWidgets('enabled + success unlocks to child', (tester) async {
    await _pump(tester, enabled: true, auth: () async => true);
    expect(find.byKey(_childKey), findsOneWidget);
  });

  testWidgets('enabled + failure keeps the lock screen', (tester) async {
    await _pump(tester, enabled: true, auth: () async => false);
    expect(find.byKey(_childKey), findsNothing);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/app_lock_gate_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the gate**

Create `app/lib/mobile/security/app_lock_gate.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

const String kAppLockPrefKey = 'app_lock_enabled';

/// Wraps the mobile app in a biometric lock. Locked on launch (and on
/// resume-from-background) when enabled; unlocks on a successful auth. The
/// [authenticator] and [enabledOverride] seams keep the state machine testable
/// without real device biometrics.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? authenticator;
  final bool? enabledOverride;

  const AppLockGate({
    super.key,
    required this.child,
    this.authenticator,
    this.enabledOverride,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _enabled = false;
  bool _locked = false;
  bool _authInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _init() async {
    final enabled = widget.enabledOverride ??
        (await SharedPreferences.getInstance()).getBool(kAppLockPrefKey) ??
        true;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = enabled;
    });
    if (enabled) _authenticate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _enabled && !_locked) {
      setState(() => _locked = true);
      _authenticate();
    }
  }

  Future<bool> _defaultAuth() async {
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: 'Unlock YourSSH',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _authenticate() async {
    if (_authInFlight) return;
    _authInFlight = true;
    final ok = await (widget.authenticator ?? _defaultAuth)();
    _authInFlight = false;
    if (mounted && ok) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text('YourSSH is locked',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _authenticate, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/app_lock_gate_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wrap the home**

In `app/lib/mobile/mobile_app.dart`, import `security/app_lock_gate.dart` and change `home:` to:
```dart
        home: const AppLockGate(child: MobileHomeShell()),
```

- [ ] **Step 6: Analyze + commit**

Run: `cd app && flutter analyze lib/mobile && flutter test test/mobile/app_lock_gate_test.dart`
Expected: clean; PASS.
```bash
git add app/lib/mobile/security/app_lock_gate.dart app/lib/mobile/mobile_app.dart app/test/mobile/app_lock_gate_test.dart
git commit -m "feat(mobile): biometric app-lock gate"
```

---

### Task 3: App-lock toggle in Settings

**Files:** Modify `app/lib/mobile/screens/mobile_settings_screen.dart`

- [ ] **Step 1: Add a Security section with a switch**

In `mobile_settings_screen.dart`:
- Import `'../security/app_lock_gate.dart';` and `'package:shared_preferences/shared_preferences.dart';`.
- Add state `bool _appLock = true;` and load it in `initState`:
```dart
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _appLock = p.getBool(kAppLockPrefKey) ?? true);
    });
  }
```
- Add a Security section before the end of the `ListView`:
```dart
            const SizedBox(height: 24),
            const Text('Security',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _appLock,
              onChanged: (v) async {
                setState(() => _appLock = v);
                final p = await SharedPreferences.getInstance();
                await p.setBool(kAppLockPrefKey, v);
              },
              title: const Text('Require biometrics to open',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text('Applies on next launch / resume',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
```
(`MobileSettingsScreen` is already a `StatefulWidget`; add the `initState` above its existing members.)

- [ ] **Step 2: Analyze + mobile tests + commit**

Run: `cd app && flutter analyze lib/mobile && flutter test test/mobile/`
Expected: clean; PASS.
```bash
git add app/lib/mobile/screens/mobile_settings_screen.dart
git commit -m "feat(mobile): app-lock toggle in settings"
```

---

## Phase M5.2 — TOFU host-key-mismatch dialog

### Task 4: TOFU watcher + dialog

**Files:**
- Create: `app/lib/mobile/security/tofu_watcher.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (wrap body in the watcher)
- Test: `app/test/mobile/tofu_watcher_test.dart`

**Interfaces:**
- Produces: `class TofuWatcher extends StatefulWidget` (`child`) — listens to `KnownHostsProvider`; when `pendingChallenge` becomes non-null it shows a single AlertDialog (old vs new fingerprint, Trust / Reject) and calls `accept()` / `reject()`.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/tofu_watcher_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'package:yourssh/mobile/security/tofu_watcher.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a dialog on host-key mismatch and Trust accepts',
      (tester) async {
    final kh = KnownHostsProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: kh,
        child: const TofuWatcher(child: Scaffold(body: SizedBox())),
      ),
    ));

    // Seed a trusted key, then present a different key for the same host.
    final fp1 = Uint8List.fromList(List.filled(16, 1));
    final fp2 = Uint8List.fromList(List.filled(16, 2));
    await kh.verifyHostKey('h', 22, 'ssh-ed25519', fp1); // first-use trust
    final future = kh.verifyHostKey('h', 22, 'ssh-ed25519', fp2); // mismatch
    await tester.pumpAndSettle();

    expect(find.textContaining('host key'), findsOneWidget);
    await tester.tap(find.text('Trust'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/tofu_watcher_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the watcher**

Create `app/lib/mobile/security/tofu_watcher.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/known_host.dart';
import '../../providers/known_hosts_provider.dart';
import '../../theme/app_theme.dart';

/// Watches [KnownHostsProvider.pendingChallenge] and shows a single TOFU
/// host-key-mismatch dialog (Trust / Reject) when a key changes.
class TofuWatcher extends StatefulWidget {
  final Widget child;
  const TofuWatcher({super.key, required this.child});

  @override
  State<TofuWatcher> createState() => _TofuWatcherState();
}

class _TofuWatcherState extends State<TofuWatcher> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final challenge = context.watch<KnownHostsProvider>().pendingChallenge;
    if (challenge != null && !_dialogOpen) {
      _dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _show(challenge));
    }
    return widget.child;
  }

  Future<void> _show(HostKeyChallenge c) async {
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Host key changed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The host key for ${c.host}:${c.port} has changed. '
                'This could be a server reinstall — or a man-in-the-middle attack.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            Text('Old: ${c.oldFingerprint}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace')),
            Text('New: ${c.newFingerprint}',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Reject')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Trust')),
        ],
      ),
    );
    if (accept == true) {
      c.accept();
    } else {
      c.reject();
    }
    _dialogOpen = false;
  }
}
```

> Verify at execution: the dialog content includes the substring "host key" (the test matches `textContaining('host key')` — the title "Host key changed" contains it case-sensitively as "Host key"; adjust the test matcher or copy so they agree — e.g. match `textContaining('host key')` against the body sentence "...host key for..." which contains lowercase "host key").

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/tofu_watcher_test.dart`
Expected: PASS.

- [ ] **Step 5: Wrap the shell body**

In `mobile_home_shell.dart`, import `'../security/tofu_watcher.dart';` and wrap the `Scaffold`'s `body: _body()` so the watcher is always mounted:
```dart
      body: TofuWatcher(child: _body()),
```

- [ ] **Step 6: Analyze + mobile tests + commit**

Run: `cd app && flutter analyze lib/mobile && flutter test test/mobile/`
Expected: clean; PASS.
```bash
git add app/lib/mobile/security/tofu_watcher.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/tofu_watcher_test.dart
git commit -m "feat(mobile): TOFU host-key-mismatch dialog"
```

---

## Phase M5.3 — Appearance settings + apply

### Task 5: Appearance section in Settings + apply to terminal

**Files:**
- Modify: `app/lib/mobile/screens/mobile_settings_screen.dart` (Appearance section)
- Modify: `app/lib/mobile/screens/mobile_sessions_screen.dart` (apply theme/font/size)
- Test: covered by analyze + existing mobile tests (the controls widget is already tested on desktop).

**Interfaces:**
- Consumes: `TerminalAppearanceControls`, `resolveTerminalAppearance`, `terminalThemeByName`, `SettingsProvider`.
- Produces: an Appearance section in mobile Settings; the mobile terminal renders with the resolved theme + font, pinch-zoom overriding only the size.

- [ ] **Step 1: Add the Appearance section to Settings**

In `mobile_settings_screen.dart`:
- Import `'../../widgets/terminal_appearance_controls.dart';`.
- Add before the closing `]` of the `ListView` (after Security):
```dart
            const SizedBox(height: 24),
            const Text('Terminal appearance',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const TerminalAppearanceControls(
                layout: AppearanceControlsLayout.rows),
```

- [ ] **Step 2: Apply appearance in the sessions terminal**

In `mobile_sessions_screen.dart`:
- Imports:
```dart
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../util/terminal_appearance.dart';
import '../../theme/terminal_themes.dart';
```
- Replace the connected `TerminalView(...)` in `_SessionBody` so it resolves appearance from settings and applies theme + font, with pinch overriding the size. Change `_SessionBody` to read settings via `context.watch<SettingsProvider>()` and compute:
```dart
    final settings = context.watch<SettingsProvider>();
    final appearance = resolveTerminalAppearance(
      host: session.host,
      globalTheme: settings.terminalTheme,
      globalFont: settings.terminalFont,
      globalFontSize: settings.fontSize,
    );
    // pinch overrides size only; theme + font come from settings.
    final effectiveSize = fontSize == 0 ? appearance.fontSize : fontSize;
```
and the TerminalView becomes:
```dart
              child: TerminalView(
                session.terminal,
                theme: terminalThemeByName(appearance.themeName),
                textStyle: TerminalStyle(
                  fontSize: effectiveSize,
                  fontFamily: appearance.fontFamily,
                ),
              ),
```
Initialize the pinch base to `0` (meaning "follow settings") in `_MobileSessionsScreenState`: change `double _fontSize = 14;` → `double _fontSize = 0;` and `double _scaleBase = 0;`; in `_onScaleStart`, seed the base from the current effective size if `_fontSize == 0` (read settings):
```dart
  void _onScaleStart(ScaleStartDetails _) {
    if (_fontSize == 0) {
      final s = context.read<SettingsProvider>();
      _fontSize = resolveTerminalAppearance(
        host: context.read<SessionProvider>().activeSshSession?.host,
        globalTheme: s.terminalTheme,
        globalFont: s.terminalFont,
        globalFontSize: s.fontSize,
      ).fontSize;
    }
    _scaleBase = _fontSize;
  }
```

> Verify at execution: pass the current `fontSize` (0 = follow-settings sentinel) from the state into `_SessionBody`. Keep `_onScaleUpdate` clamping 8–28.

- [ ] **Step 3: Analyze + mobile tests + commit**

Run: `cd app && flutter analyze lib/mobile && flutter test test/mobile/`
Expected: clean; PASS.
```bash
git add app/lib/mobile/screens/mobile_settings_screen.dart app/lib/mobile/screens/mobile_sessions_screen.dart
git commit -m "feat(mobile): terminal appearance settings + apply"
```

---

## Phase M5.4 — Release signing

### Task 6: Release signing config

**Files:** Modify `app/android/app/build.gradle.kts`

**Interfaces:** release build uses a `key.properties`-driven signing config when present, else debug signing (so unsigned debug builds still work).

- [ ] **Step 1: Add the signing config**

At the top of `app/android/app/build.gradle.kts` (above `plugins {`), add:
```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```
Inside `android { ... }` add a `signingConfigs` block (before `buildTypes`):
```kotlin
    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }
```
Change the `release` build type:
```kotlin
        release {
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
```

- [ ] **Step 2: Verify debug build still works (no key.properties)**

Run: `cd app && flutter build apk --debug`
Expected: `✓ Built ... app-debug.apk` (debug path, no key.properties needed).

- [ ] **Step 3: Document keystore generation (user step)**

The release keystore is user-provided (gitignored — `key.properties`, `*.jks` are in `app/android/.gitignore`). To sign a release later:
```
keytool -genkey -v -keystore ~/yourssh-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias yourssh
```
then create `app/android/key.properties`:
```
storePassword=<…>
keyPassword=<…>
keyAlias=yourssh
storeFile=/Users/<you>/yourssh-release.jks
```
and `flutter build apk --release` / `flutter build appbundle --release`.

- [ ] **Step 4: Commit**

```bash
git add app/android/app/build.gradle.kts
git commit -m "build(android): release signing via key.properties (debug fallback)"
```

---

### Task 7: Build + regression (v1 complete)

**Files:** none (verification)

- [ ] **Step 1: Full test suite** — `cd app && flutter test` → all pass.
- [ ] **Step 2: Analyze** — `cd app && flutter analyze` → no NEW issues (2 pre-existing probe warnings may remain).
- [ ] **Step 3: Build APK** — `cd app && flutter build apk --debug` → built.
- [ ] **Step 4: Restore regenerated desktop registrants**
```bash
git checkout HEAD -- app/macos/Flutter/GeneratedPluginRegistrant.swift app/windows/flutter/generated_plugin_registrant.cc app/windows/flutter/generated_plugins.cmake 2>/dev/null || true
```
- [ ] **Step 5: On-device (user)** — launch → biometric prompt → unlock → connect a host → change a host key server-side to see the TOFU dialog → change theme/font in Settings and see the terminal update → background/resume re-locks.

---

## Self-Review

**Spec coverage (M5):**
- "Biometric app-lock (`local_auth`) … gate on app open + resume" → Tasks 1, 2, 3. ✓
- "TOFU dialog" (mismatch) → Task 4. ✓
- "appearance settings" → Task 5 (controls + apply). ✓
- "release APK signing" → Task 6. ✓

**Placeholder scan:** No vague steps. The `> Verify at execution` notes (dialog copy vs test matcher, pinch sentinel plumbing, local_auth version) are concrete checks with stated resolutions.

**Type consistency:** `AppLockGate(child, authenticator, enabledOverride)` + `kAppLockPrefKey` used by the Settings toggle (Task 3). `TofuWatcher(child)` wraps the shell body (Task 4). `resolveTerminalAppearance(...)` args match `SettingsProvider.terminalTheme/terminalFont/fontSize` (Task 5).

## v1 complete after M5

After this milestone the Android v1 scope (M1–M5) is done. Next step (outside this plan): open a GitHub issue (English, per repo convention) for the Android target and a PR from `feat/android-mobile-app`, and update `docs/roadmap.md` Phase 5 via the `/yourssh-roadmap` skill.
