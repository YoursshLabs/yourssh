# YourSSH iOS Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the existing YourSSH mobile UI on iPhone (iOS 16+) as a signed TestFlight build, with Keychain/Face ID, background pause + reconnect, Files integration, store-compliance metadata, a URL scheme and CI.

**Architecture:** Add `app/ios` (Flutter runner) and reuse `app/lib/mobile`. Platform capability flags in `runtime_platform.dart` gate desktop-only code; the `flutter_pty` fork drops its iOS platform; no QuickJS/RDP/VNC native libs are bundled. A `MobileLifecycleCoordinator` + native background-task channel pauses/reconnects sessions; tmux defaults ON on mobile.

**Tech Stack:** Flutter 3.47.1 (CI pin), Dart, Swift (AppDelegate), CocoaPods, `flutter_secure_storage`, `local_auth`, `file_picker`, `share_plus` (new), GitHub Actions (macos runner), App Store Connect API key.

**Spec:** `docs/superpowers/specs/2026-11-12-yourssh-ios-design.md`

## Global Constraints

- Bundle id `com.thangnm.yourssh`; display name `YourSSH`; minimum iOS 16; Apple team `84T567KMYD` (SENPRINTS LLC).
- Flutter is pinned to `3.47.1` (`FLUTTER_VERSION` in CI workflows); never require 3.50.
- Keychain accessibility `first_unlock_this_device`, not synchronizable; secrets never in Documents, backups, logs or URLs.
- No JS plugin loader, QuickJS lib, RDP/VNC lib or `flutter_pty` binary in the iOS bundle.
- Platform checks use the flags in `app/lib/platform/runtime_platform.dart` (`defaultTargetPlatform`), not raw `Platform.isIOS`, except in native-channel code.
- Input to a non-connected session is rejected visibly, never buffered or replayed.
- `yourssh://` links resolve saved hosts only; `ssh://` to an unknown host needs an explicit confirmation sheet.
- `ITSAppUsesNonExemptEncryption = true`; the app is free (no IAP); no tracking; privacy manifest present.
- Conventional Commits; no `Co-Authored-By` / `Claude-Session` trailers. Signing/upload steps in `release.yml` are gated on secrets like the macOS ones.
- Tests: `cd app && flutter test`; analyze: `cd app && flutter analyze --no-fatal-infos`.

## Review Focus

1. App backgrounded with a session mid-typing or mid-SFTP-upload: session shows paused, upload fails cleanly (no half-written remote file reported as done), no keystroke is silently dropped or replayed after reconnect.
2. Foreground with many paused sessions and a server that no longer has tmux or is unreachable: reconnects are staggered, a missing tmux falls back to a plain shell with a notice, and failures end in a visible error state, not a retry storm.
3. Private keys imported or generated on iOS must not appear in the Files app (`UIFileSharingEnabled` exposes Documents) or in backups.
4. Face ID prompt: the system sheet drives the app through `inactive` → `resumed`; the lock must neither loop nor leave the app-switcher snapshot unlocked, and an unenrolled device must fall open as on Android.
5. A hostile `yourssh://connect/...` or `ssh://attacker:22` link (unknown label, ambiguous label, extra query params, huge input) never connects without confirmation and never runs a command.

---

### Task 1: Platform capability flags

**Files:**
- Modify: `app/lib/platform/runtime_platform.dart`
- Test: `app/test/platform/runtime_platform_test.dart`

**Interfaces:**
- Produces: `bool get isIOSPlatform`, `bool get supportsLocalShell`, `bool get supportsJsPlugins`, `bool get supportsRemoteDesktop`, `bool get mobileDefaultTmux` (all derived from `defaultTargetPlatform` / `isMobilePlatform`).

- [ ] **Step 1: Write the failing test**

```dart
test('iOS has no local shell, plugins or remote desktop; tmux default on', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  expect(isIOSPlatform, isTrue);
  expect(supportsLocalShell, isFalse);
  expect(supportsJsPlugins, isFalse);
  expect(supportsRemoteDesktop, isFalse);
  expect(mobileDefaultTmux, isTrue);
});
test('macOS keeps every desktop capability', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  expect(supportsLocalShell && supportsJsPlugins && supportsRemoteDesktop, isTrue);
  expect(mobileDefaultTmux, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/platform/runtime_platform_test.dart`
Expected: FAIL with "isIOSPlatform isn't defined".

- [ ] **Step 3: Implement the five getters in `runtime_platform.dart`** as in the spec's Platform guards table (`supportsRemoteDesktop` = `!isMobilePlatform` until phase 3).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/platform/runtime_platform_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/platform/runtime_platform.dart app/test/platform/runtime_platform_test.dart
git commit -m "feat: add platform capability flags for iOS"
```

### Task 2: Exclude `flutter_pty` and desktop-only code from iOS

**Files:**
- Modify: `packages/flutter_pty/pubspec.yaml:41-55` (remove the `ios:` platform entry)
- Modify: `app/lib/providers/session_provider.dart` (guard `localShell` use and RDP/VNC reconnect entry points with the flags)
- Test: `app/test/mobile/desktop_features_guard_test.dart`

**Interfaces:**
- Consumes: `supportsLocalShell`, `supportsRemoteDesktop` (Task 1).
- Produces: `MobileBootstrap` never constructs `LocalShellService`, `ScriptEngineService`, `RecordingService`, `AuditService`.

- [ ] **Step 1: Write the failing test**

```dart
test('mobile bootstrap builds no desktop-only service', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final b = MobileBootstrap();
  expect(b.sessions.localShell, isNull);
  b.dispose();
});
test('flutter_pty fork no longer declares an iOS platform', () {
  final y = File('../packages/flutter_pty/pubspec.yaml').readAsStringSync();
  expect(RegExp(r'^\s+ios:', multiLine: true).hasMatch(y), isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/desktop_features_guard_test.dart`
Expected: FAIL on the pubspec assertion (the `ios:` entry exists, `src/forkpty.c` calls `fork()`).

- [ ] **Step 3: Remove `ios:` under `plugin.platforms` in the fork's pubspec; keep android/linux/macos/windows.** In `session_provider.dart` make `reconnectRdp`/`reconnectVnc` and any `localShell` use no-ops when the matching flag is false.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/desktop_features_guard_test.dart && flutter analyze --no-fatal-infos`
Expected: PASS, no new warnings.

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_pty/pubspec.yaml app/lib/providers/session_provider.dart app/test/mobile/desktop_features_guard_test.dart
git commit -m "feat: keep flutter_pty and desktop-only features out of the iOS build"
```

### Task 3: iOS runner scaffold

**Files:**
- Create: `app/ios/**` (via `cd app && flutter create --platforms=ios --org com.thangnm --project-name yourssh .`, then fix the bundle id to exactly `com.thangnm.yourssh`)
- Modify: `app/ios/Podfile` (`platform :ios, '16.0'`), `app/ios/Runner.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET = 16.0`, `DEVELOPMENT_TEAM = 84T567KMYD`), `app/ios/Runner/Info.plist` (`CFBundleDisplayName` = `YourSSH`), `tool/gen_app_icons.py` (emit `Assets.xcassets/AppIcon.appiconset` from `assets/branding/yourssh_icon.svg`, opaque, no alpha, 1024 marketing icon)
- Test: `app/test/platform/ios_runner_config_test.dart`

**Interfaces:**
- Produces: a runner that builds with `flutter build ios --simulator --no-codesign`.

- [ ] **Step 1: Write the failing test** (file-content assertions)

```dart
test('runner config', () {
  final proj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  expect(proj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.thangnm.yourssh;'));
  expect(proj, contains('IPHONEOS_DEPLOYMENT_TARGET = 16.0;'));
  expect(File('ios/Podfile').readAsStringSync(), contains("platform :ios, '16.0'"));
  expect(File('ios/Runner/Info.plist').readAsStringSync(),
      contains('<string>YourSSH</string>'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/platform/ios_runner_config_test.dart`
Expected: FAIL (no `ios/` directory).

- [ ] **Step 3: Generate and edit the files above; extend `gen_app_icons.py` idempotently (never hand-edit PNGs, see CLAUDE.md "App icon").** Add `app/ios/Pods/` and `app/ios/Flutter/ephemeral/` to ignores if `flutter create` did not.

- [ ] **Step 4: Run the test, then the real build**

Run: `cd app && flutter test test/platform/ios_runner_config_test.dart && flutter build ios --simulator --no-codesign`
Expected: PASS; build succeeds and shows `YourSSH.app`.

- [ ] **Step 5: Commit**

```bash
git add app/ios tool/gen_app_icons.py app/test/platform/ios_runner_config_test.dart
git commit -m "feat: add iOS runner (bundle id com.thangnm.yourssh, iOS 16)"
```

### Task 4: Mobile UI boots on iPhone

**Files:**
- Modify: `app/lib/main.dart:119-124` (mobile branch unchanged in shape; verify no desktop call precedes it), `app/lib/mobile/**` only where a Material/Android assumption breaks on iOS (safe areas, back gesture, keyboard inset)
- Test: `app/test/mobile/ios_boot_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3.

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('iOS boots the mobile shell without desktop services', (t) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  await t.pumpWidget(const YourSSHMobileApp());
  await t.pump();
  expect(find.byType(MobileHomeShell), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails or passes as baseline**

Run: `cd app && flutter test test/mobile/ios_boot_test.dart`
Expected: FAIL only if a desktop plugin is touched on the mobile path; fix it by guarding with the flags.

- [ ] **Step 3: Run on a simulator (`flutter run -d <iPhone simulator>`) and fix layout problems found in hosts, terminal (accessory bar above the keyboard, pinch zoom), SFTP, snippets, keys, settings.** Record each fix in the commit message body.

- [ ] **Step 4: Run test + full suite**

Run: `cd app && flutter test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib app/test/mobile/ios_boot_test.dart
git commit -m "fix: make the mobile UI run cleanly on iPhone"
```

### Task 5: Keychain accessibility and Face ID

**Files:**
- Modify: `app/lib/services/storage_service.dart:27` (add `iOptions`), `app/lib/providers/ai_chat_provider.dart:50-69` (same), `app/ios/Runner/Info.plist` (`NSFaceIDUsageDescription` = "Unlock YourSSH with Face ID to protect your servers and keys.")
- Test: `app/test/services/storage_service_ios_options_test.dart`, `app/test/mobile/app_lock_gate_test.dart`

**Interfaces:**
- Produces: `static const IOSOptions StorageService.iosKeychainOptions` = `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device, synchronizable: false)`.

- [ ] **Step 1: Write the failing tests**

```dart
test('iOS keychain is this-device-only and not synced', () {
  expect(StorageService.iosKeychainOptions.params['accessibility'], 'first_unlock_this_device');
  expect(StorageService.iosKeychainOptions.params['synchronizable'], 'false');
});
testWidgets('unlock sheet driving inactive->resumed does not re-lock loop', (t) async {
  var calls = 0;
  await t.pumpWidget(MaterialApp(home: AppLockGate(
    enabledOverride: true,
    authenticator: () async { calls++; return true; },
    child: const Text('in'))));
  await t.pumpAndSettle();
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await t.pumpAndSettle();
  expect(calls, lessThanOrEqualTo(2));
  expect(find.text('in'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/storage_service_ios_options_test.dart test/mobile/app_lock_gate_test.dart`
Expected: FAIL with "iosKeychainOptions isn't defined".

- [ ] **Step 3: Implement `iosKeychainOptions` and pass `iOptions:` to both `FlutterSecureStorage` constructors; leave the existing plaintext-fallback accounting unchanged.** The lock gate already guards `_authInFlight`; adjust only if the second test fails.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services test/mobile/app_lock_gate_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/storage_service.dart app/lib/providers/ai_chat_provider.dart app/ios/Runner/Info.plist app/test
git commit -m "feat: this-device-only Keychain options and Face ID usage string for iOS"
```

### Task 6: Mobile defaults (tmux ON) and Ed25519-only key generation

**Files:**
- Modify: `app/lib/providers/settings_provider.dart:111` (first-launch default), `app/lib/services/key_gen_service.dart` (add `supportedAlgorithms`), `app/lib/mobile/screens/mobile_keys_screen.dart:327-330`
- Test: `app/test/providers/settings_provider_test.dart`, `app/test/services/key_gen_service_test.dart`

**Interfaces:**
- Consumes: `mobileDefaultTmux` (Task 1).
- Produces: `Future<List<String>> KeyGenService.supportedAlgorithms()` → `['ed25519']` when `probeSshKeygen()` is false, else `['ed25519','rsa','ecdsa']`.

- [ ] **Step 1: Write the failing tests**

```dart
test('tmux defaults on for mobile, user choice wins', () async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues({});
  expect((await SettingsProvider.loadedForTest()).tmuxEnabled, isTrue);
  SharedPreferences.setMockInitialValues({'tmuxEnabled': false});
  expect((await SettingsProvider.loadedForTest()).tmuxEnabled, isFalse);
});
test('no ssh-keygen -> ed25519 only', () async {
  final s = KeyGenService(probe: () async => false);
  expect(await s.supportedAlgorithms(), ['ed25519']);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/settings_provider_test.dart test/services/key_gen_service_test.dart`
Expected: FAIL (missing members). Reuse the file's existing way of loading settings if `loadedForTest` does not exist; keep assertions identical.

- [ ] **Step 3: Implement.** In `settings_provider.dart` use `prefs.getBool('tmuxEnabled') ?? mobileDefaultTmux`. Add an optional injectable probe to `KeyGenService`'s constructor and `supportedAlgorithms()`; make `_AlgoOption`s in the keys screen come from it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers test/services test/mobile`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib app/test
git commit -m "feat: tmux auto-attach default on mobile; Ed25519-only key generation without ssh-keygen"
```

### Task 7: Background pause, foreground reconnect

**Files:**
- Create: `app/lib/mobile/lifecycle/background_task_channel.dart`, `app/lib/mobile/lifecycle/mobile_lifecycle_coordinator.dart`, `app/ios/Runner/AppDelegate.swift` (channel `com.thangnm.yourssh/background`: `begin` → Int id via `UIApplication.beginBackgroundTask(expirationHandler:)`, `end(id)`)
- Modify: `app/lib/models/ssh_session.dart:8` (`SessionStatus.paused`), `app/lib/providers/session_provider.dart` (`pauseAll`, `resumePaused`), `app/lib/mobile/mobile_app.dart` (mount coordinator), `app/lib/mobile/screens/mobile_terminal_screen.dart` (banner + input rejection)
- Test: `app/test/mobile/mobile_lifecycle_coordinator_test.dart`, `app/test/mobile/mobile_terminal_paused_test.dart`

**Interfaces:**
- Consumes: `SessionProvider.sshSessions`, `reconnectSession(String id)` (existing), `PortForwardService.stopForHost` / `autoStartAll`.
- Produces:
  - `abstract class BackgroundTasks { Future<int> begin(); Future<void> end(int id); }`
  - `class MobileLifecycleCoordinator(SessionProvider sessions, PortForwardService forwards, PortForwardProvider forwardProvider, BackgroundTasks tasks, {Duration stagger = const Duration(milliseconds: 300)})` with `Future<void> onBackground()` and `Future<void> onForeground()`
  - `void SessionProvider.pauseAll()`, `Future<void> SessionProvider.resumePaused({Duration stagger})`
  - `bool SshSession.acceptsInput` (true only when `status == connected`)

- [ ] **Step 1: Write the failing tests**

```dart
test('background marks connected sessions paused and ends the task', () async {
  final f = fakeSessionsWith(connected: 2);          // helper in test/helpers
  final tasks = FakeBackgroundTasks();
  final c = MobileLifecycleCoordinator(f.sessions, f.forwards, f.forwardProvider, tasks);
  await c.onBackground();
  expect(f.sessions.sshSessions.every((s) => s.status == SessionStatus.paused), isTrue);
  expect(tasks.began, 1);
  expect(tasks.ended, [tasks.lastId]);
});
test('foreground reconnects paused sessions in order, staggered', () async {
  /* 3 paused sessions, stagger 10ms: reconnectSession called for ids in
     order, never concurrently more than once per stagger, forwards restarted */
});
test('paused session rejects input and nothing is buffered', () {
  final s = pausedSession();
  expect(s.acceptsInput, isFalse);
  expect(ssh.sendInput(s.id, 'ls\n'), isFalse);
  expect(s.pendingInputBytes, 0);
});
testWidgets('terminal shows banner while paused', (t) async {
  /* pump MobileTerminalScreen with paused session */
  expect(find.text('Session paused — reconnecting'), findsOneWidget);
});
test('a session in error state is not auto-resumed', () async {
  /* status error before background stays error after onForeground */
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/mobile_lifecycle_coordinator_test.dart test/mobile/mobile_terminal_paused_test.dart`
Expected: FAIL with "MobileLifecycleCoordinator not defined".

- [ ] **Step 3: Implement the signatures above.** `onBackground`: `begin()` first, then `forwardProvider`/`forwards` stop accepting, in-flight `SftpTransferService` jobs are failed with a "paused" message, `pauseAll()`, then `end(id)` in a `finally` (the Swift expiration handler also calls `endBackgroundTask`). `onForeground`: wait for the lock gate to be unlocked, then `resumePaused(stagger)` calling the existing reconnect path (which already honors `settings.reconnectAttempts` and the tmux flag), then `autoStartAll`. Register the coordinator as a `WidgetsBindingObserver` in `YourSSHMobileApp` state; it ignores lifecycle changes while `AppLockGate` is authenticating (reuse the gate's in-flight guard via a shared `ValueNotifier<bool> authInFlight`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile test/providers`
Expected: PASS. Manual check on a simulator: background 40 s, return, session reconnects into the same tmux window.

- [ ] **Step 5: Commit**

```bash
git add app/lib app/ios/Runner/AppDelegate.swift app/test
git commit -m "feat: pause sessions on iOS background and reconnect on foreground"
```

### Task 8: Private key storage and Files integration

**Files:**
- Create: `app/lib/mobile/files/app_paths.dart`
- Modify: `app/lib/mobile/screens/mobile_keys_screen.dart:315-320` (`_keysDir`), `app/lib/mobile/screens/mobile_sftp_screen.dart:195-240` (`_download`, `_upload`), `app/pubspec.yaml` (add `share_plus`), `app/ios/Runner/Info.plist` (`UIFileSharingEnabled` = true, `LSSupportsOpeningDocumentsInPlace` = true)
- Test: `app/test/mobile/app_paths_test.dart`, `app/test/mobile/mobile_sftp_screen_test.dart`

**Interfaces:**
- Produces:
  - `Future<Directory> AppPaths.privateKeysDir()` — `<ApplicationSupport>/keys`, created 0700, marked excluded from backup
  - `Future<Directory> AppPaths.downloadsDir()` — `<Documents>/Downloads`
  - `Future<void> shareFile(BuildContext context, String path)` (share sheet via `share_plus`)
  - `Future<int> migrateLegacyKeys(Directory from, Directory to)` — moves `<Documents>/YourSSH/keys/*` and returns the count moved

- [ ] **Step 1: Write the failing tests**

```dart
test('keys live outside Documents', () async {
  final keys = await AppPaths.privateKeysDir();
  final docs = await getApplicationDocumentsDirectory();
  expect(p.isWithin(docs.path, keys.path), isFalse);
});
test('downloads land in Documents/Downloads and use safeLocalChild', () async {
  final d = await AppPaths.downloadsDir();
  expect(p.basename(d.path), 'Downloads');
  expect(() => safeLocalChild(d.path, '../x'), throwsA(isA<UnsafeRemotePathException>()));
});
test('legacy keys move out of Documents and keep mode 0600', () async {
  /* seed old dir with a key, run migrateLegacyKeys, assert old dir empty,
     new file mode & 0x1ff == 0x180 */
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/app_paths_test.dart`
Expected: FAIL (`AppPaths` not defined). Use the repo's `path_provider` platform-interface fake for dir lookups.

- [ ] **Step 3: Implement.** `_keysDir()` delegates to `AppPaths.privateKeysDir()` and runs `migrateLegacyKeys` once. `_download` writes to `downloadsDir()` (no directory picker on iOS) and offers a share action that calls `shareFile`; `_upload` and key import keep `FilePicker.platform.pickFiles` (the iOS document picker). Use `private_temp.dart` helpers where a temp copy is needed.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib app/pubspec.yaml app/pubspec.lock app/ios/Runner/Info.plist app/test
git commit -m "feat: keep private keys out of the Files-visible Documents; iOS download/share/import"
```

### Task 9: Usage strings, ATS and privacy manifest

**Files:**
- Modify: `app/ios/Runner/Info.plist`
- Create: `app/ios/Runner/PrivacyInfo.xcprivacy` (add to the Runner target resources in `project.pbxproj`)
- Test: `app/test/platform/ios_plist_test.dart`

**Interfaces:**
- Produces Info.plist keys: `NSCameraUsageDescription` ("Scan a YourSSH QR code to import hosts from your computer."), `NSLocalNetworkUsageDescription` ("Connect to your computer on the local network to import hosts."), `NSFaceIDUsageDescription` (Task 5), `ITSAppUsesNonExemptEncryption` = `true`, `NSAppTransportSecurity` → `NSAllowsLocalNetworking` = `true` (no `NSAllowsArbitraryLoads`).
- Privacy manifest: `NSPrivacyTracking` = false, `NSPrivacyCollectedDataTypes` empty array, `NSPrivacyAccessedAPITypes` = UserDefaults `CA92.1`, FileTimestamp `C617.1` (add `35F9.1` SystemBootTime only if a dependency needs it).

- [ ] **Step 1: Write the failing test**

```dart
test('Info.plist and privacy manifest carry the required entries', () {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  for (final k in ['NSCameraUsageDescription','NSLocalNetworkUsageDescription',
      'NSFaceIDUsageDescription','ITSAppUsesNonExemptEncryption',
      'UIFileSharingEnabled','LSSupportsOpeningDocumentsInPlace']) {
    expect(plist, contains('<key>$k</key>'));
  }
  expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
  final pm = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
  expect(pm, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
  expect(pm, contains('CA92.1'));
  expect(pm, contains('C617.1'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/platform/ios_plist_test.dart`
Expected: FAIL (missing keys / file).

- [ ] **Step 3: Add the keys and the manifest file exactly as listed above.**

- [ ] **Step 4: Run test, then `flutter build ios --simulator --no-codesign`**

Run: `cd app && flutter test test/platform/ios_plist_test.dart`
Expected: PASS; the build log shows no privacy-manifest warnings from Runner.

- [ ] **Step 5: Commit**

```bash
git add app/ios app/test/platform/ios_plist_test.dart
git commit -m "feat: iOS usage strings, ATS local-networking exception and privacy manifest"
```

### Task 10: `yourssh://` and `ssh://` links

**Files:**
- Create: `app/lib/mobile/links/url_router.dart`, `app/lib/mobile/links/link_coordinator.dart`
- Modify: `app/ios/Runner/Info.plist` (`CFBundleURLTypes`: `yourssh`, `ssh`), `app/ios/Runner/AppDelegate.swift` (forward `application(_:open:options:)` and cold-start URL to Dart over channel `com.thangnm.yourssh/links`), `app/lib/mobile/mobile_app.dart`
- Test: `app/test/mobile/url_router_test.dart`

**Interfaces:**
- Produces:
  - `sealed class MobileLink` with `ConnectLink(String hostRef)`, `SftpLink(String hostRef, String? path)`, `SshLink(String user, String host, int port)`
  - `MobileLink? parseMobileLink(Uri uri)` — pure; `null` for anything else
  - `HostMatch resolveHostRef(String ref, List<Host> hosts)` → `HostMatch.one(Host)` / `.none` / `.ambiguous(List<Host>)` (id, then case-insensitive label)
  - `LinkCoordinator(HostProvider, SessionProvider, Future<bool> Function(SshLink) confirm).handle(MobileLink)`

- [ ] **Step 1: Write the failing tests**

```dart
test('parses connect and sftp links', () {
  expect(parseMobileLink(Uri.parse('yourssh://connect/prod-db')), isA<ConnectLink>());
  final l = parseMobileLink(Uri.parse('yourssh://sftp/prod-db?path=/var/log')) as SftpLink;
  expect(l.path, '/var/log');
});
test('rejects tunnels, commands, imports, other schemes and oversized input', () {
  for (final u in ['yourssh://tunnel/start/x','yourssh://exec/h?cmd=id',
      'yourssh://import?u=http://x','http://x','yourssh://connect/${'a' * 5000}']) {
    expect(parseMobileLink(Uri.parse(u)), isNull);
  }
});
test('ambiguous label resolves to ambiguous, never to a connection', () {
  expect(resolveHostRef('db', [hostLabeled('DB'), hostLabeled('db')]), isA<HostAmbiguous>());
});
test('yourssh:// to an unknown host does not connect', () async { /* sessions untouched */ });
test('ssh:// unknown host connects only after confirm returns true', () async {
  /* confirm false -> no session; confirm true -> one connect, target shown to confirm */
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/url_router_test.dart`
Expected: FAIL with "parseMobileLink not defined".

- [ ] **Step 3: Implement the signatures.** Semantics are those of `docs/superpowers/specs/2026-11-12-yourssh-cli-design.md` ("URL scheme", on branch `feature/cli`): saved hosts only for `yourssh://`; refs capped at 256 chars; unknown query keys ignored; `ssh://` is honored only when the Settings toggle "Handle ssh:// links" is on (default off), and an unknown target always goes through `confirm`. Connect through the existing `SessionProvider` path so TOFU prompts still apply.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/url_router_test.dart`
Expected: PASS. Manual: `xcrun simctl openurl booted "yourssh://connect/<label>"` opens the session.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/links app/lib/mobile/mobile_app.dart app/ios app/test/mobile/url_router_test.dart
git commit -m "feat: yourssh:// and optional ssh:// links on iOS (saved hosts only)"
```

### Task 11: Bundle exclusion check and simulator CI

**Files:**
- Create: `tool/check_ios_bundle.sh` (args: path to `.app`; fails if the bundle or its `Frameworks` contain `qjsbridge`, `yourssh_rdp`, `yourssh_vnc`, `flutter_pty` or `libquickjs`, or if `strings` on the Runner binary finds `forkpty`)
- Modify: `.github/workflows/pr-test.yml` (new `ios` job; add it to the aggregate `test` job's `needs` and checks)
- Test: `app/test/tooling/check_ios_bundle_test.dart` (runs the script against a temp directory)

**Interfaces:**
- Produces: job `ios` on `macos-latest`: checkout, `subosito/flutter-action` with `${{ env.FLUTTER_VERSION }}`, `flutter pub get`, `flutter test test/mobile test/platform`, `flutter build ios --simulator --no-codesign`, then `bash tool/check_ios_bundle.sh app/build/ios/iphonesimulator/Runner.app`. Pin actions by the same SHAs as the existing jobs.

- [ ] **Step 1: Write the failing test**

```dart
test('script rejects a bundle containing the QuickJS bridge', () async {
  final d = Directory.systemTemp.createTempSync();
  File('${d.path}/Frameworks/libqjsbridge.dylib').createSync(recursive: true);
  final r = await Process.run('bash', ['../tool/check_ios_bundle.sh', d.path]);
  expect(r.exitCode, isNot(0));
});
test('script accepts a clean bundle', () async {
  final d = Directory.systemTemp.createTempSync();
  File('${d.path}/Runner').createSync();
  expect((await Process.run('bash', ['../tool/check_ios_bundle.sh', d.path])).exitCode, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tooling/check_ios_bundle_test.dart`
Expected: FAIL (script missing).

- [ ] **Step 3: Implement the script and the workflow job.** The `test` aggregate must stay red unless `ios` is green (`[ "${{ needs.ios.result }}" = "success" ] || exit 1`).

- [ ] **Step 4: Run the test and the script on a real simulator build**

Run: `cd app && flutter test test/tooling && flutter build ios --simulator --no-codesign && bash ../tool/check_ios_bundle.sh build/ios/iphonesimulator/Runner.app`
Expected: PASS and exit 0.

- [ ] **Step 5: Commit**

```bash
git add tool/check_ios_bundle.sh .github/workflows/pr-test.yml app/test/tooling
git commit -m "ci: iOS simulator build, tests and bundle exclusion check in pr-test"
```

### Task 12: Signed IPA and TestFlight upload in release.yml

**Files:**
- Modify: `.github/workflows/release.yml` (new `build-ios` job, `needs: test`, `runs-on: macos-latest`)
- Create: `app/ios/ExportOptions.plist` (`method` = `app-store-connect`, `teamID` = `84T567KMYD`, `signingStyle` = `manual`, provisioning profile name for `com.thangnm.yourssh`)
- Test: `app/test/tooling/release_ios_job_test.dart`

**Interfaces:**
- Secrets (job gated like `MACOS_SIGNING`; unset → the job still builds unsigned and skips signing/upload): `IOS_DISTRIBUTION_P12_BASE64`, `IOS_DISTRIBUTION_P12_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`.
- Steps: import cert into a temporary keychain (same pattern as the macOS job), install the profile, `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist --build-number=${{ github.run_number }} --split-debug-info=build/symbols`, `bash tool/check_ios_bundle.sh` on the archived `.app`, upload with `xcrun altool --upload-app -f <ipa> -t ios --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID`, then upload the IPA and the symbols zip as workflow artifacts. The `release` job's `needs` list is NOT extended (iOS goes to TestFlight, not to the GitHub release page).

- [ ] **Step 1: Write the failing test** (workflow text assertions)

```dart
test('release.yml has a gated build-ios job', () {
  final y = File('../.github/workflows/release.yml').readAsStringSync();
  expect(y, contains('build-ios:'));
  expect(y, contains('IOS_SIGNING:'));
  expect(y, contains('84T567KMYD'));
  expect(y, contains('altool --upload-app'));
  expect(y, contains('check_ios_bundle.sh'));
  expect(y, isNot(contains('NSAllowsArbitraryLoads')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tooling/release_ios_job_test.dart`
Expected: FAIL (`build-ios:` missing).

- [ ] **Step 3: Add the job and `ExportOptions.plist`.** Secrets are only read inside steps with `if: env.IOS_SIGNING == 'true'`; never echo them; delete the temporary keychain and `AuthKey_*.p8` in an `if: always()` step.

- [ ] **Step 4: Run test, then validate the workflow**

Run: `cd app && flutter test test/tooling/release_ios_job_test.dart && (command -v actionlint >/dev/null && actionlint ../.github/workflows/release.yml || true)`
Expected: PASS; actionlint reports no errors if installed. The first real upload needs the repo secrets and an App Store Connect record under team `84T567KMYD`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml app/ios/ExportOptions.plist app/test/tooling/release_ios_job_test.dart
git commit -m "ci: signed iOS IPA and TestFlight upload gated on secrets"
```

## Self-Review

- Spec coverage: guards/exclusions (T1, T2, T11), runner and min iOS (T3), UI on iPhone (T4), Keychain/Face ID (T5), tmux default + key generation (T6), background pause/reconnect (T7), Files/picker/share (T8), usage strings/ATS/privacy manifest/encryption declaration (T9), URL scheme (T10), simulator CI (T11), TestFlight (T12). iPad, hardware keyboard, Secure Enclave, App Store submission, RDP/VNC, mosh, App Intents are phase 2/3 and deliberately absent.
- Type consistency: `supportsLocalShell`/`supportsRemoteDesktop`/`mobileDefaultTmux` (T1) are used in T2, T6; `SessionStatus.paused` and `acceptsInput` (T7) are the only new session members; `AppPaths` (T8) is the sole key-directory source.
- Proportion: signatures and assertions only; Swift bodies and workflow YAML are left to the builder per the spec.
