# YourSSH iOS Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the existing YourSSH mobile UI on iPhone (iOS 16+) as a signed TestFlight build, with Keychain/Face ID, background grace + pause + reconnect, Files integration, store-compliance metadata, `yourssh://` (and opt-in `ssh://`) links and CI.

**Architecture:** Add `app/ios` (Flutter 3.50 runner, UIScene lifecycle) and reuse `app/lib/mobile` (forui, touch theme). Platform capability flags in `runtime_platform.dart` gate desktop-only code; the `flutter_pty` fork drops its iOS platform; no QuickJS/RDP/VNC native libs are bundled; `main()` already returns for mobile before the CLI lock, sandbox migration and window setup. One native class (`YourSshNative.swift`) owns the method channels. A `MobileLifecycleCoordinator` gives backgrounded sessions a grace window, then pauses them and reconnects on foreground; tmux defaults ON for fresh mobile installs. Links reuse the desktop `CliServer` + `UrlChannel`.

**Tech Stack:** Flutter 3.50.0 (CI pin), Dart, forui 0.27 via `yourssh_ui`, Swift (UIScene: `FlutterImplicitEngineDelegate`, `FlutterSceneLifeCycleDelegate`), Swift Package Manager + CocoaPods, `flutter_secure_storage` 9.2, `local_auth` 2.3, `file_picker` 8.3, `mobile_scanner` (Apple Vision line), `share_plus` (new), GitHub Actions (macOS runner), App Store Connect API key.

**Spec:** `docs/superpowers/specs/2026-11-12-yourssh-ios-design.md` (refreshed 2026-11-13 against `develop` @ `8c6f0cd1`).

## Global Constraints

- Bundle id `com.thangnm.yourssh`; display name `YourSSH`; minimum iOS 16; iPhone only (`TARGETED_DEVICE_FAMILY = 1`); Apple team `84T567KMYD` (SENPRINTS LLC).
- Flutter is pinned to `3.50.0` (`FLUTTER_VERSION` in `pr-test.yml` and `release.yml`, kept equal). This plan does not bump Flutter or the Android toolchain.
- The iOS runner is the Flutter 3.50 UIScene template (`AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate`, `SceneDelegate: FlutterSceneDelegate`). Native code registers in `didInitializeImplicitFlutterEngine` through `YourSshNative` and gets URLs from scene events; never `application(_:open:options:)`.
- Keychain: `IOSOptions(accessibility: first_unlock_this_device, synchronizable: false)`; no plaintext `SharedPreferences` fallback on iOS. The macOS legacy-Keychain options (`macOsKeychainOptions`) stay as they are. Secrets never in Documents, backups (`UserDefaults` included), logs or URLs.
- No JS plugin loader, QuickJS lib, RDP/VNC lib or `flutter_pty` binary in the iOS bundle; no subprocess (`Process.run`) on iOS.
- Desktop-only infrastructure never runs on iOS: the CLI socket/pipe listener and single-instance lock (`main()` returns for mobile first), `UpdateService`/`UpdateProvider`, the macOS sandbox migration, `migratePlaintextSecrets`, audit, recordings.
- Platform checks use the flags in `app/lib/platform/runtime_platform.dart` (`defaultTargetPlatform`), not raw `Platform.isIOS`, except in native-channel code.
- Input to a non-connected session is rejected visibly, never buffered or replayed.
- `yourssh://` links go through the existing `CliServer` + `UrlChannel` (`app/lib/services/cli/`): no second parser or resolver. `ssh://` is opt-in and never connects to an unknown target.
- UI: forui widgets / `Ys*` components, `YsColors` tokens (not the deprecated `MobileColors`), `FLucideIcons`, touch `FItem`s ≥ 44 px; toasts via `AppSnack`/`showYsToast`, dialogs via `showYsDialog`/`showYsConfirm`, sheets via `showFSheet`. `bash tool/check_ui_lint.sh` must pass (no `IconButton(`, `AlertDialog(`, `SnackBar(`, `Icons.`, `ScaffoldMessenger`, `showDialog(`, `showModalBottomSheet`, `TextField(`, no `Color(0x…)` in widgets).
- Widget tests: `ysTestApp(child, touch: true)` (`app/test/helpers/ys_test_app.dart`) or a `MaterialApp` with `builder: ysRootBuilderTouch`; iOS behavior via `variant: TargetPlatformVariant.only(TargetPlatform.iOS)` (plain `test()`s may set `debugDefaultTargetPlatformOverride` with a `tearDown` reset). The secure-storage channel is mocked as in `app/test/providers/session_provider_test.dart`.
- `ITSAppUsesNonExemptEncryption = true`; the app is free (no IAP); no tracking; privacy manifest present; no `NSAppTransportSecurity` exceptions.
- Conventional Commits; no `Co-Authored-By` / `Claude-Session` trailers. Signing/upload steps in `release.yml` are gated on secrets like the macOS ones.
- Commands: tests `cd app && flutter test`; analyze `cd app && flutter analyze --no-fatal-infos`; UI lint `bash tool/check_ui_lint.sh`; iOS builds `cd app && flutter build ios --simulator --no-codesign` and `flutter build ios --release --no-codesign`.
- Verification labels: **Local** runs on the owner's Mac (Xcode 27.2, iOS 27.2 SDK, CocoaPods 1.17, **no simulator runtime**: builds and `flutter test` work, launching does not). **CI-only** runs in the pr-test `ios` job (Task 12) on a macOS runner with simulators. **Manual** needs a booted simulator or a device and is not runnable on the owner's Mac today.

## Review Focus

1. App backgrounded mid-typing or mid-SFTP-transfer: inside the grace window nothing changes; after it, sessions show paused, an upload fails with a "failed" toast (never reported as done), a download leaves no partial file, and no keystroke is silently dropped or replayed after reconnect.
2. Foreground with many paused sessions and a server that no longer has tmux or is unreachable: reconnects are staggered, a session that died while still marked connected is caught by the keepalive probe, a missing tmux leaves a plain shell with the shell's own error, failures end in a visible error state, and a pause never fires `onSessionDropped` or burns reconnect attempts.
3. Private keys imported or generated on iOS must not appear in the Files app (`UIFileSharingEnabled` exposes Documents), in backups, or linger in the picker's temp copy; a failed Keychain write must not land in `UserDefaults`.
4. Face ID lock: it covers every pushed route and dialog (not only the home route), the app-switcher snapshot, and never loops on its own sheet's `inactive` → `resumed`; an unenrolled device falls open as on Android; the lock screen lives outside the Navigator, so nothing on it may need an `Overlay`.
5. A hostile `yourssh://connect/...` or `ssh://attacker:22` link (unknown label, ambiguous label, extra query params, userinfo, huge input, control/bidi characters) never connects without confirmation, never runs a command, and an unknown `ssh://` target only ever reaches a prefilled Add Host screen.
6. Nothing desktop-only starts on iOS: no `cli.token`/socket, no update banner or check, no plugin loader.

---

### Task 1: Platform capability flags

**Files:**
- Modify: `app/lib/platform/runtime_platform.dart`
- Test: `app/test/platform/runtime_platform_test.dart` (existing file; it already resets the override in `tearDown`)

**Interfaces:**
- Produces: `bool get isIOSPlatform`, `bool get supportsRemoteDesktop` (= `!isMobilePlatform` until phase 3), `bool get supportsSubprocesses` (= `!isIOSPlatform`), `bool get mobileDefaultTmux` (= `isMobilePlatform`), all derived from `defaultTargetPlatform` / `isMobilePlatform`. No other flags: each has a consumer in this plan (Tasks 2, 7, 9).

- [ ] **Step 1: Write the failing tests** (append to the existing `main()`)

```dart
test('iOS: no subprocesses or remote desktop; tmux default on', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  expect(isIOSPlatform, isTrue);
  expect(supportsSubprocesses, isFalse);
  expect(supportsRemoteDesktop, isFalse);
  expect(mobileDefaultTmux, isTrue);
});
test('Android: subprocesses yes, remote desktop no, tmux default on', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  expect(isIOSPlatform, isFalse);
  expect(supportsSubprocesses, isTrue);
  expect(supportsRemoteDesktop, isFalse);
  expect(mobileDefaultTmux, isTrue);
});
test('macOS keeps every desktop capability', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  expect(isIOSPlatform, isFalse);
  expect(supportsSubprocesses && supportsRemoteDesktop, isTrue);
  expect(mobileDefaultTmux, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/platform/runtime_platform_test.dart`
Expected: FAIL with "isIOSPlatform isn't defined". (**Local**)

- [ ] **Step 3: Implement the four getters** next to `isMobilePlatform`, each with a one-line doc comment naming its consumer.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/platform/runtime_platform_test.dart`
Expected: PASS (**Local**)

- [ ] **Step 5: Commit**

```bash
git add app/lib/platform/runtime_platform.dart app/test/platform/runtime_platform_test.dart
git commit -m "feat: add platform capability flags for iOS"
```

### Task 2: Keep desktop-only code off the mobile path

**Files:**
- Modify: `packages/flutter_pty/pubspec.yaml:45-46` (remove `ios:` / `ffiPlugin: true` under `flutter.plugin.platforms`; keep android/linux/macos/windows)
- Create: `app/lib/mobile/navigation/open_session.dart`
- Modify: `app/lib/mobile/screens/mobile_hosts_screen.dart:310-356` (`_openSession` → `openMobileSession`), `app/lib/mobile/screens/mobile_terminal_screen.dart:160-215` (the host picker sheet lists only hosts `canOpenOnMobile` accepts)
- Test: `app/test/mobile/desktop_only_guard_test.dart`, `app/test/mobile/open_session_test.dart`

**Interfaces:**
- Consumes: `supportsRemoteDesktop` (Task 1).
- Produces:
  - `bool canOpenOnMobile(Host host)` — `host.protocol == HostProtocol.ssh || supportsRemoteDesktop`
  - `Future<void> openMobileSession(NavigatorState nav, Host host, {String auditSource = 'app', bool resetStack = false})` — refuses a host `canOpenOnMobile` rejects with `AppSnack.info(nav.context, 'RDP and VNC hosts open in the desktop app')`; otherwise the current `_openSession` behavior (reuse the host's live SSH session or `SessionProvider.connectAny(host, auditSource: auditSource)` without awaiting it, then push `MobileTerminalScreen(focusSessionId:, onOpenFiles:, onOpenPortForward:)`); `resetStack` pops to the first route before pushing (used by links, Task 11). `SessionProvider` is read from `nav.context` (the providers sit above `MaterialApp`).
- Guard contract: no file under `app/lib/mobile` imports `/main.dart'`, `main_screen.dart`, `single_instance.dart`, `cli_listener`, `peer_cred.dart`, `app_cli_handlers.dart`, `update_service.dart`, `update_provider.dart`, `local_shell_service.dart`, `pty_runner.dart`, `/recording_`, `/audit_`, `/plugin_`, `yourssh_script_engine`, `window_manager`, `hotkey_manager`, `local_notifier`. (`cli_server.dart`, `url_channel.dart`, `host_resolver.dart`, `cli_handlers.dart`, `link_refused.dart` are allowed.)

- [ ] **Step 1: Write the failing tests**

```dart
// desktop_only_guard_test.dart (cwd is app/)
test('flutter_pty fork no longer declares an iOS platform', () {
  final y = File('../packages/flutter_pty/pubspec.yaml').readAsStringSync();
  expect(RegExp(r'^\s+ios:', multiLine: true).hasMatch(y), isFalse);
});
test('app/lib/mobile imports no desktop-only module', () {
  const banned = ["/main.dart'", 'main_screen.dart', 'single_instance.dart',
    'cli_listener', 'peer_cred.dart', 'app_cli_handlers.dart', 'update_service.dart',
    'update_provider.dart', 'local_shell_service.dart', 'pty_runner.dart',
    '/recording_', '/audit_', '/plugin_', 'yourssh_script_engine',
    'window_manager', 'hotkey_manager', 'local_notifier'];
  final offenders = [
    for (final f in Directory('lib/mobile').listSync(recursive: true)
        .whereType<File>().where((f) => f.path.endsWith('.dart')))
      for (final l in f.readAsLinesSync().where((l) => l.startsWith('import ')))
        if (banned.any(l.contains)) '${f.path}: $l',
  ];
  expect(offenders, isEmpty);
});
test('main() returns for mobile before any desktop start-up', () {
  final src = File('lib/main.dart').readAsStringSync();
  final start = src.indexOf('void main(');
  final mobile = src.indexOf('runApp(const YourSSHMobileApp())', start);
  expect(mobile, greaterThan(start));
  for (final call in ['claimSingleInstance(', '_migrateSandboxContainer(',
      'windowManager.ensureInitialized', 'NotificationService.init']) {
    expect(src.indexOf(call, start), greaterThan(mobile), reason: call);
  }
});

// open_session_test.dart
testWidgets('an RDP host is refused on mobile: notice, no session, no route',
    (t) async {
  /* MultiProvider(SessionProvider over SshService(StorageService())) above
     MaterialApp(builder: ysRootBuilderTouch, home: a button calling
     openMobileSession(Navigator.of(ctx), Host(..., protocol: HostProtocol.rdp))) */
  expect(sessions.sessions, isEmpty);
  expect(find.text('RDP and VNC hosts open in the desktop app'), findsOneWidget);
  expect(find.byType(MobileTerminalScreen), findsNothing);
}, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
testWidgets('an SSH host with a live session reuses it', (t) async {
  /* existing session for the host -> MobileTerminalScreen pushed,
     no second connectAny (sessions.sessions.length unchanged) */
}, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/desktop_only_guard_test.dart test/mobile/open_session_test.dart`
Expected: FAIL on the pubspec assertion and "openMobileSession isn't defined"; the import and `main()` guards already pass (they pin today's state). (**Local**)

- [ ] **Step 3: Implement.** Remove the fork's `ios:` entry (leave `packages/flutter_pty/ios/` on disk; without the pubspec entry neither CocoaPods nor SPM builds it). Move `_openSession`'s body into `openMobileSession`; `MobileHostsScreen` calls it with `Navigator.of(context)`; the terminal screen's host picker filters with `canOpenOnMobile`. `MobileAddHostScreen._saveAndConnect` (`:196-205`) only creates SSH hosts and needs no change.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile && flutter analyze --no-fatal-infos && bash ../tool/check_ui_lint.sh`
Expected: PASS, no new warnings, lint clean. (**Local**)

- [ ] **Step 5: Commit**

```bash
git add packages/flutter_pty/pubspec.yaml app/lib/mobile app/test/mobile
git commit -m "feat: keep flutter_pty and desktop-only features off the mobile path"
```

### Task 3: iOS runner scaffold (UIScene) and native entry point

**Files:**
- Create: `app/ios/**` via `cd app && flutter create --platforms=ios --org com.thangnm --project-name yourssh .` (Flutter 3.50 template: `Runner/AppDelegate.swift` with `FlutterImplicitEngineDelegate`, `Runner/SceneDelegate.swift`, `UIApplicationSceneManifest` in `Info.plist`); the bundle id must be exactly `com.thangnm.yourssh` (tests target: `com.thangnm.yourssh.RunnerTests`)
- Create: `app/ios/Runner/YourSshNative.swift` (`final class YourSshNative: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate` with `static func register(with registrar: FlutterPluginRegistrar)` that calls `registrar.addSceneDelegate(instance)`; no channels yet — Tasks 8, 9, 11 add them), added to the Runner target in `project.pbxproj`
- Modify: `app/ios/Runner/AppDelegate.swift` (`didInitializeImplicitFlutterEngine`: after `GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)`, `YourSshNative.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "YourSshNative")!)`), `app/ios/Podfile` (uncomment `platform :ios, '16.0'`), `app/ios/Runner.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET = 16.0` in every configuration, `DEVELOPMENT_TEAM = 84T567KMYD` on Runner, `TARGETED_DEVICE_FAMILY = 1` everywhere), `app/ios/Runner/Info.plist` (`CFBundleDisplayName` = `YourSSH`; drop `UISupportedInterfaceOrientations~ipad`), `tool/gen_app_icons.py` (emit `app/ios/Runner/Assets.xcassets/AppIcon.appiconset` from `assets/branding/yourssh_icon.svg`: opaque, no alpha, the 1024 marketing icon, idempotent like the other targets), `app/analysis_options.yaml` (`ios/**` under `analyzer.exclude`; `flutter pub get` adds it — commit it), `app/pubspec.yaml` + `app/pubspec.lock` (`mobile_scanner`, see Step 3)
- Test: `app/test/platform/ios_runner_config_test.dart`

**Interfaces:**
- Produces: a runner that builds with `flutter build ios --simulator --no-codesign` and `flutter build ios --release --no-codesign` (output `build/ios/iphonesimulator/Runner.app` / `build/ios/iphoneos/Runner.app` — the product is `Runner.app`; the home-screen name comes from `CFBundleDisplayName`); the `YourSshNative` registration point.

- [ ] **Step 1: Write the failing test** (file-content assertions; runs on any OS)

```dart
test('runner config', () {
  final proj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  expect(proj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.thangnm.yourssh;'));
  Set<String> all(String key) => RegExp('$key = "?([^";]+)"?;')
      .allMatches(proj).map((m) => m[1]!).toSet();
  expect(all('IPHONEOS_DEPLOYMENT_TARGET'), {'16.0'});
  expect(all('TARGETED_DEVICE_FAMILY'), {'1'});
  expect(proj, contains('DEVELOPMENT_TEAM = 84T567KMYD;'));
  expect(proj, contains('YourSshNative.swift in Sources'));
  expect(File('ios/Podfile').readAsStringSync(),
      contains("\nplatform :ios, '16.0'"));
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  expect(plist, matches(RegExp(
      r'<key>CFBundleDisplayName</key>\s*<string>YourSSH</string>')));
  expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
  expect(File('ios/Runner/AppDelegate.swift').readAsStringSync(),
      allOf(contains('didInitializeImplicitFlutterEngine'),
          contains('YourSshNative.register')));
  final lock = File('ios/Podfile.lock');
  if (lock.existsSync()) {
    expect(lock.readAsStringSync(), isNot(contains('GoogleMLKit')));
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/platform/ios_runner_config_test.dart`
Expected: FAIL (no `ios/` directory). (**Local**)

- [ ] **Step 3: Generate and edit the files above.** Extend `gen_app_icons.py` idempotently (never hand-edit PNGs, CLAUDE.md "App icon"); add `app/ios/Pods/`, `app/ios/Flutter/ephemeral/` and `app/ios/.symlinks/` to ignores if `flutter create` did not. `mobile_scanner` is locked at 5.2.3, whose iOS podspec depends on `GoogleMLKit/BarcodeScanning ~> 6.0.0` (large binary, ML Kit's own data-collection disclosures, historically no arm64-simulator slice): bump it in `app/pubspec.yaml` to the newest release whose iOS implementation uses Apple Vision (read its CHANGELOG; no `GoogleMLKit` in `ios/Podfile.lock` afterwards) and adapt `mobile_qr_scan_screen.dart` to any API change; its tests (`app/test/mobile/screens/`) must stay green and the pr-test `android` job (`flutter build apk --debug`) proves Android still builds.

- [ ] **Step 4: Run the test, then the real builds**

Run: `cd app && flutter test test/platform/ios_runner_config_test.dart test/mobile && flutter build ios --simulator --no-codesign && flutter build ios --release --no-codesign`
Expected: PASS; both builds succeed and produce `Runner.app`. (**Local** — no simulator runtime is needed to build.) Launching: **Manual** (`flutter run -d <iPhone simulator>`; the app opens on the hosts tab).

- [ ] **Step 5: Commit**

```bash
git add app/ios app/analysis_options.yaml app/pubspec.yaml app/pubspec.lock app/lib/mobile tool/gen_app_icons.py app/test/platform/ios_runner_config_test.dart
git commit -m "feat: add iOS runner (bundle id com.thangnm.yourssh, iOS 16, UIScene)"
```

### Task 4: Mobile UI boots on iPhone

**Files:**
- Modify: `app/lib/mobile/**` only where an iOS-platform widget test or the simulator smoke run (Task 12) shows a Material/Android assumption breaking (safe areas, back-swipe on pushed routes, keyboard inset above the accessory bar, iOS text-selection controls); every change follows the UI rules in Global Constraints
- Test: `app/test/mobile/ios_boot_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3.

- [ ] **Step 1: Write the test**

```dart
testWidgets('the mobile shell boots under iOS without desktop services',
    (t) async {
  SharedPreferences.setMockInitialValues({kAppLockPrefKey: false});
  PackageInfo.setMockInitialValues(appName: 'YourSSH', packageName:
      'com.thangnm.yourssh', version: '0.0.0', buildNumber: '0',
      buildSignature: '');
  // secure-storage channel mocked as in session_provider_test.dart
  await t.pumpWidget(const YourSSHMobileApp());
  await t.pumpAndSettle();
  expect(find.byType(MobileHomeShell), findsOneWidget);
  expect(find.byType(MobileTabBar), findsOneWidget);
}, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
testWidgets('every tab renders under iOS', (t) async {
  /* same setup; tap each MobileTab (Hosts, Snippets, Keys, Settings),
     pumpAndSettle, expect(t.takeException(), isNull) */
}, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
```

- [ ] **Step 2: Run test (baseline)**

Run: `cd app && flutter test test/mobile/ios_boot_test.dart`
Expected: PASS, or FAIL only where a widget assumes Android; fix that widget (no platform branches unless the iOS behavior is intended). (**Local**)

- [ ] **Step 3: Check the screens on an iPhone simulator** — hosts, terminal (accessory bar above the keyboard, pinch zoom, long-press cursor drag), SFTP, snippets, keys, settings, toasts above `MobileTabBar`, notch/home-indicator safe areas, back-swipe. **Manual** (not runnable on the owner's Mac); the CI smoke test (Task 12) covers launch + hosts tab automatically. Record each fix in the commit body.

- [ ] **Step 4: Run tests + full suite**

Run: `cd app && flutter test && flutter analyze --no-fatal-infos && bash ../tool/check_ui_lint.sh`
Expected: PASS (**Local**)

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile app/test/mobile/ios_boot_test.dart
git commit -m "fix: make the mobile UI run cleanly on iPhone"
```

### Task 5: Keychain options and no plaintext fallback on iOS

**Files:**
- Modify: `app/lib/services/storage_service.dart:27-30` (`iOptions:` on the `static const _storage`), `:76-90` (`_saveSecret`), constructor; `app/lib/mobile/mobile_bootstrap.dart:44` (`StorageService(allowPlaintextFallback: !isIOSPlatform)`); the mobile screens that save secrets — `mobile_add_host_screen.dart` (`_save`/`_saveAndConnect`, `:190-205`), `mobile_keys_screen.dart` (`:155`, `:312` passphrase saves), `mobile_sync_screen.dart` (sync code save), `mobile_qr_scan_screen.dart` (import) — catch `SecretStoreException` and show `AppSnack.error(context, 'Could not save to the iOS Keychain')`
- Test: `app/test/services/storage_service_test.dart` (existing; it already mocks `plugins.it_nomads.com/flutter_secure_storage`)

**Interfaces:**
- Produces:
  - `static const IOSOptions StorageService.iosKeychainOptions` = `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device, synchronizable: false)` (default account name)
  - `StorageService({bool allowPlaintextFallback = true})`; when false, a failed secure write throws `SecretStoreException(String key, Object cause)` and writes nothing to `SharedPreferences` (reads keep their prefs fallback)
  - `class SecretStoreException implements Exception`
- `AiChatProvider` is desktop-only (not in `MobileBootstrap`): unchanged.

- [ ] **Step 1: Write the failing tests**

```dart
test('iOS keychain is this-device-only and not synced', () {
  expect(StorageService.iosKeychainOptions.params['accessibility'],
      'first_unlock_this_device');
  expect(StorageService.iosKeychainOptions.params['synchronizable'], 'false');
});
test('without plaintext fallback a failed secure write throws and prefs stay clean',
    () async {
  /* channel handler throws PlatformException(code: '-25300') on 'write' */
  final s = StorageService(allowPlaintextFallback: false);
  await expectLater(s.savePassword('h1', 'pw'),
      throwsA(isA<SecretStoreException>()));
  expect((await SharedPreferences.getInstance()).containsKey('pw_h1'), isFalse);
  expect(s.hasPlaintextSecrets, isFalse);
});
test('the default still falls back to prefs (desktop/Android unchanged)',
    () async {
  /* same failing channel; StorageService() -> prefs has pw_h1,
     hasPlaintextSecrets true */
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/storage_service_test.dart`
Expected: FAIL with "iosKeychainOptions isn't defined". (**Local**)

- [ ] **Step 3: Implement** the options, the constructor flag, the exception and the mobile call-site toasts; leave the plaintext accounting (`_markPlaintext`, `migratePlaintextSecrets`) unchanged for desktop.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services test/mobile && bash ../tool/check_ui_lint.sh`
Expected: PASS (**Local**). On a device/simulator, a saved password survives an app relaunch (**Manual**).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/storage_service.dart app/lib/mobile app/test/services/storage_service_test.dart
git commit -m "feat: this-device-only Keychain and no plaintext secret fallback on iOS"
```

### Task 6: App lock covers every route; Face ID usage string

**Files:**
- Modify: `app/lib/mobile/mobile_app.dart` (`home: const MobileHomeShell()`, `builder: (c, child) => ysRootBuilderTouch(c, AppLockGate(child: child ?? const SizedBox.shrink()))`), `app/lib/mobile/security/app_lock_gate.dart` (while locked: `Stack` of the child wrapped in `Offstage` + `TickerMode(enabled: false)`, and the lock screen; the child is never unmounted), `app/ios/Runner/Info.plist` (`NSFaceIDUsageDescription` = "Unlock YourSSH with Face ID to protect your servers and keys.")
- Test: `app/test/mobile/app_lock_gate_test.dart` (existing; update "nothing behind it" to "behind it but offstage"), `app/test/mobile/mobile_home_shell_test.dart` / `home_shell_test.dart` if they pump `YourSSHMobileApp`

**Interfaces:**
- `AppLockGate` keeps its constructor (`child`, `authenticator`, `enabledOverride`) and its lifecycle rules (lock on `inactive`/`hidden`/`paused`, re-auth on `resumed`, `_authInFlight` guard, fall open when `isDeviceSupported()` is false). The lock screen sits outside the Navigator: no tooltips/popovers (no `Overlay` there).

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('a pushed route is covered while locked and survives the unlock',
    (t) async {
  final nav = GlobalKey<NavigatorState>();
  var allow = false;
  await t.pumpWidget(MaterialApp(
    navigatorKey: nav,
    theme: ysMaterialTheme(),
    builder: (c, child) => ysRootBuilderTouch(c, AppLockGate(
        enabledOverride: true, authenticator: () async => allow,
        child: child!)),
    home: const Text('home'),
  ));
  await t.pumpAndSettle();                       // auth failed: locked
  nav.currentState!.push(MaterialPageRoute(builder: (_) => const Text('terminal')));
  await t.pumpAndSettle();
  expect(find.text('YourSSH is locked'), findsOneWidget);
  expect(find.text('terminal'), findsNothing);   // offstage: not painted
  expect(find.text('terminal', skipOffstage: false), findsOneWidget);
  allow = true;
  await t.tap(find.text('Unlock'));
  await t.pumpAndSettle();
  expect(find.text('terminal'), findsOneWidget);
});
testWidgets('backgrounding re-locks over the current route without a prompt loop',
    (t) async {
  /* authenticator counts calls and returns true; push 'terminal';
     handleAppLifecycleStateChanged(inactive) + pump -> 'terminal' offstage;
     resumed + pumpAndSettle -> 'terminal' visible, calls == 2 */
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/app_lock_gate_test.dart`
Expected: FAIL: the pushed route is visible above the lock (today the gate is the home route). (**Local**)

- [ ] **Step 3: Implement** the builder placement and the offstage child; add the Face ID string to `Info.plist`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile && bash ../tool/check_ui_lint.sh`
Expected: PASS (**Local**). App-switcher snapshot shows the lock screen; Face ID prompt does not loop (**Manual**, device with Face ID or simulator with enrolled Face ID).

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile app/ios/Runner/Info.plist app/test/mobile
git commit -m "fix: app lock covers every route; Face ID usage string for iOS"
```

### Task 7: Mobile tmux default; Ed25519-only key generation without subprocesses

**Files:**
- Modify: `app/lib/providers/settings_provider.dart:121` (first-run default), `app/lib/mobile/screens/mobile_settings_screen.dart` (Terminal group: `SettingsRow` "Keep sessions in tmux", `toggle: settings.tmuxEnabled`, `onToggle: (v) => settings.save(tmuxEnabled: v)`, Lucide icon, `YsColors`), `app/lib/services/key_gen_service.dart:23-26` (constructor), `:61-70` (`probeSshKeygen`), `app/lib/mobile/mobile_bootstrap.dart` (`KeyGenService(chmod: supportsSubprocesses ? null : chmodNative)`), `app/lib/mobile/screens/mobile_keys_screen.dart:268-271, :330-336` (options from `supportedAlgorithms()`)
- Create: `app/lib/util/native_chmod.dart`
- Test: `app/test/providers/settings_provider_tmux_test.dart`, `app/test/services/key_gen_service_test.dart` (existing), `app/test/util/native_chmod_test.dart`

**Interfaces:**
- Consumes: `mobileDefaultTmux`, `supportsSubprocesses` (Task 1).
- Produces:
  - `SettingsProvider` load rule: no stored `tmuxEnabled` + `mobileDefaultTmux` + no `yourssh.hosts` key → `tmuxEnabled = true` and persisted; no stored value otherwise → `false` (persisted on mobile so the decision is made once, like `terminalTheme`); a stored value always wins
  - `Future<List<String>> KeyGenService.supportedAlgorithms()` → `['ed25519']` when `probeSshKeygen()` is false, else `['ed25519', 'rsa', 'ecdsa']`
  - `KeyGenService.probeSshKeygen()` returns false without spawning a process when `!supportsSubprocesses`
  - `Future<void> chmodNative(String path, int mode)` — libc `chmod` through `dart:ffi` (`DynamicLibrary.process()`; `mode_t` is `Uint16` on iOS/macOS, `Uint32` on Linux/Android); throws `FileSystemException` with `errno` on failure; unsupported on Windows

- [ ] **Step 1: Write the failing tests**

```dart
// settings_provider_tmux_test.dart — tearDown resets the override
test('fresh mobile install: tmux on, decided once', () async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  SharedPreferences.setMockInitialValues({});
  final p = SettingsProvider();
  await pumpEventQueue();
  expect(p.tmuxEnabled, isTrue);
  expect((await SharedPreferences.getInstance()).getBool('tmuxEnabled'), isTrue);
});
test('existing mobile install without a choice keeps tmux off', () async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  SharedPreferences.setMockInitialValues({'yourssh.hosts': '[]'});
  final p = SettingsProvider();
  await pumpEventQueue();
  expect(p.tmuxEnabled, isFalse);
});
test('a stored choice wins', () async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  SharedPreferences.setMockInitialValues({'tmuxEnabled': false});
  final p = SettingsProvider();
  await pumpEventQueue();
  expect(p.tmuxEnabled, isFalse);
});

// key_gen_service_test.dart
test('iOS: ed25519 only and ssh-keygen is never probed', () async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  final s = KeyGenService();
  expect(await s.probeSshKeygen(), isFalse);
  expect(await s.supportedAlgorithms(), ['ed25519']);
});
// The injected-chmod path of generateEd25519 is already covered by the
// existing 'key is restricted before key material is written' test.

// native_chmod_test.dart (skip on Windows)
test('chmodNative sets owner-only modes', () async {
  final f = File('${tmp.path}/k')..writeAsStringSync('x');
  await chmodNative(f.path, 0x180);
  expect(f.statSync().mode & 0x1ff, 0x180);
}, skip: Platform.isWindows);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/settings_provider_tmux_test.dart test/services/key_gen_service_test.dart test/util/native_chmod_test.dart`
Expected: FAIL (missing members / file). (**Local**)

- [ ] **Step 3: Implement.** In `_load`, mirror the `terminalTheme` first-run block for `tmuxEnabled`. The keys screen's `_AlgoOption` list comes from `supportedAlgorithms()`. Never call `Process.run` on iOS from the mobile path.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers test/services test/util test/mobile && bash ../tool/check_ui_lint.sh`
Expected: PASS (**Local**; `native_chmod_test` also runs on the macOS runner in Task 12, which exercises the `Uint16` Darwin signature). Generating an Ed25519 key on the simulator works (**Manual**).

- [ ] **Step 5: Commit**

```bash
git add app/lib app/test
git commit -m "feat: tmux default for fresh mobile installs; Ed25519-only key generation without subprocesses"
```

### Task 8: Background grace, pause, foreground resume

**Files:**
- Create: `app/lib/mobile/lifecycle/background_tasks.dart`, `app/lib/mobile/lifecycle/mobile_lifecycle_coordinator.dart`
- Modify: `app/ios/Runner/YourSshNative.swift` (channel `yourssh/background`: `begin` → `["id": Int, "remainingMs": Int]` via `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)` and `backgroundTimeRemaining` (`-1` when not finite); the expiration handler ends the task; `end(id)`), `app/lib/models/ssh_session.dart` (`paused`, `acceptsInput`), `app/lib/providers/session_provider.dart` (`pauseAll`, `resumePaused`, `verifyLive`; early return for a paused session after `openShell` returns (`:569`) and in the `catch` (`:589`); `@visibleForTesting void addSessionForTest(SshSession s)`), `app/lib/services/ssh_service.dart` (`isAlive`), `app/lib/mobile/mobile_app.dart` (iOS only: build the coordinator with `MethodChannelBackgroundTasks`, an `AppLifecycleListener(onPause: c.onBackground, onResume: c.onForeground)`, dispose both), `app/lib/mobile/screens/mobile_terminal_screen.dart` (`_SessionBody` non-connected branch: "Session paused — reconnecting" for `session.paused`; `_openPanel` insert/key callbacks check `acceptsInput` and toast "Session is not connected"), `app/lib/mobile/screens/mobile_snippets_screen.dart:127-133` (`sendInput` false → `AppSnack.info(context, 'Session is not connected')`)
- Test: `app/test/mobile/mobile_lifecycle_coordinator_test.dart`, `app/test/providers/session_provider_pause_test.dart`, `app/test/mobile/mobile_terminal_paused_test.dart`

**Interfaces:**
- Consumes: `SessionProvider.sshSessions`, `reconnectSession(String id)` (`:645`, reuses the tab, cancels pending timers, honors tmux and retry settings), `SshService.disconnect(hostId)` (`:1456`), `SshService.sendInput` (`:1446`, returns false without a live shell), `PortForwardService.isRunning/start/stopAll`, `PortForwardProvider.forwards`, `SSHClient.ping()` (dartssh2 fork).
- Produces:
  - `class BackgroundLease { final int id; final Duration? remaining; }` (`remaining` null = unknown)
  - `abstract class BackgroundTasks { Future<BackgroundLease?> begin(); Future<void> end(int id); }` and `MethodChannelBackgroundTasks` on `MethodChannel('yourssh/background')` (`begin` returning null when the OS refuses)
  - `MobileLifecycleCoordinator({required SessionProvider sessions, required PortForwardService forwards, required PortForwardProvider forwardRules, required BackgroundTasks tasks, Duration stagger = const Duration(milliseconds: 300), Duration maxGrace = const Duration(seconds: 25)})` with `Future<void> onBackground()`, `Future<void> onForeground()`, `void dispose()`; grace = `min(remaining − 5 s, maxGrace)` clamped at zero, zero when there is no lease
  - `void SessionProvider.pauseAll()` — every SSH session that is `connected` or `connecting` (reconnect countdown) gets `paused = true`, `status = disconnected`, its reconnect/countdown timers cancelled and a dim `[Paused while YourSSH was in the background]` line; each affected host's client closed once; sessions in `error` or a user-closed `disconnected` state untouched
  - `Future<void> SessionProvider.resumePaused({Duration stagger})` — in tab order: `paused = false`, `reconnectSession(id)`, wait `stagger`; ignores the auto-reconnect setting (a pause is not a drop)
  - `Future<void> SessionProvider.verifyLive({Duration timeout = const Duration(seconds: 3)})` — per host with a `connected` session: `await _ssh.isAlive(hostId, timeout: timeout)`; false → pause that host's sessions and resume them
  - `Future<bool> SshService.isAlive(String hostId, {Duration timeout})` — false when there is no client, it is closed, or `ping()` does not complete in time
  - `bool SshSession.paused` (default false); `bool get SshSession.acceptsInput` → `status == SessionStatus.connected && !paused`

- [ ] **Step 1: Write the failing tests**

```dart
// mobile_lifecycle_coordinator_test.dart — SessionProvider / PortForwardService
// subclasses record calls; FakeBackgroundTasks hands out leases; fake_async.
test('a quick app switch pauses nothing and ends the task', () => fakeAsync((fa) {
  c.onBackground(); fa.elapse(const Duration(seconds: 10));
  c.onForeground(); fa.flushMicrotasks();
  expect(sessions.calls, isNot(contains('pauseAll')));
  expect(tasks.ended, [tasks.lastId]);
}));
test('grace expiry stops forwards, then pauses sessions, then ends the task',
    () => fakeAsync((fa) {
  c.onBackground(); fa.elapse(const Duration(seconds: 25)); fa.flushMicrotasks();
  expect(log, ['forwards.stopAll', 'sessions.pauseAll', 'tasks.end']);
}));
test('grace follows the OS allowance', () => fakeAsync((fa) {
  /* lease remaining 12 s -> pauseAll at 7 s, not before */
}));
test('foreground resumes paused sessions, probes the rest, restarts recorded forwards',
    () => fakeAsync((fa) {
  /* 2 forwards were running at pause -> after onForeground:
     ['sessions.resumePaused', 'sessions.verifyLive', 'forwards.start:a', 'forwards.start:b'] */
}));

// session_provider_pause_test.dart — SshService subclass: connect() records the
// host and never completes; disconnect() records the host id.
test('pauseAll pauses connected and reconnecting sessions, closes each host once',
    () { /* 2 sessions on host A, 1 on B, 1 in error -> paused 3, disconnect [A, B],
            error session untouched, no onSessionDropped */ });
test('a paused session whose shell closes schedules no reconnect', () async {
  /* paused flag set before openShell returns -> no countdown text,
     status stays disconnected, onSessionDropped not called */ });
test('resumePaused reconnects in tab order, stagger apart, even with auto-reconnect off',
    () async { /* settings autoReconnectEnabled -> false; connect() calls ordered */ });
test('paused session rejects input and nothing is buffered', () {
  expect(s.acceptsInput, isFalse);
  expect(ssh.sendInput(s.id, 'ls\n'), isFalse);
});

// mobile_terminal_paused_test.dart
testWidgets('terminal shows the paused state and mounts no TerminalView', (t) async {
  expect(find.text('Session paused — reconnecting'), findsOneWidget);
  expect(find.byType(TerminalView), findsNothing);
}, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/mobile_lifecycle_coordinator_test.dart test/providers/session_provider_pause_test.dart test/mobile/mobile_terminal_paused_test.dart`
Expected: FAIL with "MobileLifecycleCoordinator isn't defined". (**Local**)

- [ ] **Step 3: Implement the signatures above.** `onBackground`: `begin()`, then start the grace timer; when it fires, record `forwardRules.forwards.where((f) => forwards.isRunning(f.id))`, `await forwards.stopAll()` (before any client closes, so its 2–30 s reconnect backoff never starts), `sessions.pauseAll()`, then `end(id)` in a `finally`. `onForeground`: cancel the timer, `end` the lease if still open, `await sessions.resumePaused(stagger: stagger)`, `await sessions.verifyLive()`, then `forwards.start` each recorded rule. Reconnecting does not wait for the lock gate. `inactive` is never acted on (Face ID sheet, Control Center). Android keeps today's behavior (no coordinator).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile test/providers test/services && flutter analyze --no-fatal-infos && bash ../tool/check_ui_lint.sh`
Expected: PASS (**Local**). On a simulator or device: background 10 s → the session is untouched; background 60 s → paused line, return → reconnects into the same tmux window and the port forward is back (**Manual**).

- [ ] **Step 5: Commit**

```bash
git add app/lib app/ios/Runner/YourSshNative.swift app/test
git commit -m "feat: background grace, pause and foreground reconnect on iOS"
```

### Task 9: Private key storage and Files integration

**Files:**
- Create: `app/lib/mobile/files/app_paths.dart`, `app/lib/mobile/files/file_export.dart`
- Modify: `app/lib/mobile/screens/mobile_keys_screen.dart:133-157` (`_importKey`: copy, register the copy, `FilePicker.platform.clearTemporaryFiles()`), `:322-327` (`_keysDir` → `AppPaths.privateKeysDir()`), `app/lib/mobile/screens/mobile_sftp_screen.dart:199-240` (`_download`: iOS → `AppPaths.downloadsDir()` + `uniqueLocalPath`, Android keeps `FilePicker.platform.getDirectoryPath()`; both stream through `writeDownload`; on iOS the success toast has a "Share" action calling `shareFile`; `_upload` clears picker temp files when done), `app/ios/Runner/YourSshNative.swift` (channel `yourssh/files`: `excludeFromBackup(path)` sets `URLResourceValues.isExcludedFromBackup = true`), `app/pubspec.yaml` + `pubspec.lock` (add `share_plus`), `app/ios/Runner/Info.plist` (`UIFileSharingEnabled` = true, `LSSupportsOpeningDocumentsInPlace` = true)
- Test: `app/test/mobile/app_paths_test.dart`, `app/test/mobile/file_export_test.dart`

**Interfaces:**
- Consumes: `chmodNative`, `supportsSubprocesses`, `isIOSPlatform` (Tasks 1, 7), `safeLocalChild` / `UnsafeRemotePathException` (`app/lib/util/safe_local_path.dart`), `KeyProvider.addKeyFromFile(path, label)`.
- Produces:
  - `AppPaths.privateKeysDir({ChmodFn? chmod, Future<void> Function(String path)? excludeFromBackup})` → `<ApplicationSupport>/keys`, created, 0700, excluded from backup (default `excludeFromBackup` = the `yourssh/files` channel on iOS, no-op elsewhere; default `chmod` = `chmodNative` when `!supportsSubprocesses`, else `chmodLocal`)
  - `AppPaths.downloadsDir()` → `<Documents>/Downloads`, created
  - `Future<File> importPrivateKey(String pickedPath, Directory into, {ChmodFn? chmod})` — copies (never moves) to a unique sanitized name in `into`, 0600
  - `String uniqueLocalPath(String dir, String name)` — `safeLocalChild(dir, name)`, then `name (1).ext`, `name (2).ext`… until free
  - `Future<void> writeDownload(Stream<List<int>> data, String finalPath)` — writes `finalPath.part`, renames on success, deletes it on any error and rethrows
  - `Future<void> shareFile(BuildContext context, String path)` — `share_plus` share sheet (pass `sharePositionOrigin` from the context's render box)
- No legacy key migration: iOS has no earlier install; Android's Documents directory is app-private and its existing keys stay where they are.

- [ ] **Step 1: Write the failing tests**

```dart
// app_paths_test.dart — fake PathProviderPlatform as in
// app/test/widgets/keychain_screen_test.dart (docs + support paths)
test('keys live outside Documents; downloads inside it', () async {
  final keys = await AppPaths.privateKeysDir(
      chmod: (_, _) async {}, excludeFromBackup: (_) async {});
  expect(p.isWithin(docs.path, keys.path), isFalse);
  expect((await AppPaths.downloadsDir()).path, p.join(docs.path, 'Downloads'));
});
test('the key directory is 0700 and excluded from backup', () async {
  /* records chmod (path, 0x1C0) and excludeFromBackup(path) for keys dir */
});
test('importPrivateKey copies with 0600 and never overwrites', () async {
  /* picked file stays; second import of the same name -> 'id_ed25519 (1)';
     injected chmod saw 0x180 */
});

// file_export_test.dart
test('uniqueLocalPath never overwrites and rejects unsafe names', () {
  /* 'a.txt' exists -> 'a (1).txt'; '../x' -> throwsA(isA<UnsafeRemotePathException>()) */
});
test('writeDownload leaves nothing behind when the stream fails', () async {
  final c = StreamController<List<int>>();
  final f = writeDownload(c.stream, '${tmp.path}/out.bin');
  c..add([1, 2])..addError(Exception('connection closed'));
  await expectLater(f, throwsException);
  expect(File('${tmp.path}/out.bin').existsSync(), isFalse);
  expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/app_paths_test.dart test/mobile/file_export_test.dart`
Expected: FAIL (`AppPaths` not defined). (**Local**)

- [ ] **Step 3: Implement** the files and the screen changes; Android keeps its directory picker but gets `writeDownload`. `ChmodFn` is `Future<void> Function(String path, int mode)` (the `KeyGenService` constructor type).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile && bash ../tool/check_ui_lint.sh && flutter build ios --simulator --no-codesign`
Expected: PASS; build succeeds with `share_plus` (**Local**). In the Files app, "On My iPhone › YourSSH" shows only `Downloads` (**Manual**).

- [ ] **Step 5: Commit**

```bash
git add app/lib app/pubspec.yaml app/pubspec.lock app/ios app/test
git commit -m "feat: keep private keys out of Files and backups; iOS download/share/import"
```

### Task 10: Usage strings, encryption flag and privacy manifest

**Files:**
- Modify: `app/ios/Runner/Info.plist`
- Create: `app/ios/Runner/PrivacyInfo.xcprivacy` (added to the Runner target's resources in `project.pbxproj`)
- Test: `app/test/platform/ios_plist_test.dart`

**Interfaces:**
- Produces Info.plist keys: `NSCameraUsageDescription` ("Scan the QR code YourSSH shows on your computer to import hosts."), `NSLocalNetworkUsageDescription` ("YourSSH connects to SSH servers and to your computer on the local network to import or share hosts."), `NSFaceIDUsageDescription` (Task 6), `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` (Task 9), `ITSAppUsesNonExemptEncryption` = `true`. **No** `NSAppTransportSecurity`: all networking is `dart:io`, which ATS does not cover.
- Privacy manifest: `NSPrivacyTracking` = false, `NSPrivacyTrackingDomains` empty, `NSPrivacyCollectedDataTypes` empty array, `NSPrivacyAccessedAPITypes` = UserDefaults `CA92.1`, FileTimestamp `C617.1` (add SystemBootTime `35F9.1` only if a dependency needs it).

- [ ] **Step 1: Write the failing test**

```dart
test('Info.plist and privacy manifest carry the required entries', () {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  for (final k in ['NSCameraUsageDescription', 'NSLocalNetworkUsageDescription',
      'NSFaceIDUsageDescription', 'UIFileSharingEnabled',
      'LSSupportsOpeningDocumentsInPlace']) {
    expect(plist, contains('<key>$k</key>'));
  }
  expect(plist, matches(RegExp(
      r'<key>ITSAppUsesNonExemptEncryption</key>\s*<true/>')));
  expect(plist, isNot(contains('NSAppTransportSecurity')));
  final pm = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
  expect(pm, matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')));
  expect(pm, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
  expect(pm, contains('CA92.1'));
  expect(pm, contains('C617.1'));
  expect(File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      contains('PrivacyInfo.xcprivacy in Resources'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/platform/ios_plist_test.dart`
Expected: FAIL (missing keys / file). (**Local**)

- [ ] **Step 3: Add the keys and the manifest exactly as listed above.**

- [ ] **Step 4: Run test, then build and lint the bundle's plist**

Run: `cd app && flutter test test/platform/ios_plist_test.dart && flutter build ios --release --no-codesign && plutil -lint build/ios/iphoneos/Runner.app/Info.plist && test -f build/ios/iphoneos/Runner.app/PrivacyInfo.xcprivacy`
Expected: PASS; `OK` from plutil; the manifest is in the bundle (**Local**). Purpose-string (ITMS-90683) and required-reason (ITMS-91053) warnings are only reported by App Store Connect on the first upload (Task 13); fix them there (plugin build flags preferred over new permission strings).

- [ ] **Step 5: Commit**

```bash
git add app/ios app/test/platform/ios_plist_test.dart
git commit -m "feat: iOS usage strings, encryption declaration and privacy manifest"
```

### Task 11: `yourssh://` and opt-in `ssh://` links

**Files:**
- Create: `app/lib/mobile/links/mobile_cli_handlers.dart`, `app/lib/mobile/links/ssh_link.dart`, `app/lib/mobile/links/mobile_links.dart`
- Modify: `app/ios/Runner/YourSshNative.swift` (`scene(_:willConnectTo:options:)` cold-start `urlContexts` and `scene(_:openURLContexts:)` route by scheme: `yourssh` → channel `yourssh/url`, `ssh` → `yourssh/ssh_url`; each forwards `open(String)` and queues the newest 8 until Dart calls `ready` — the contract of `app/macos/Runner/MainFlutterWindow.swift`), `app/ios/Runner/Info.plist` (`CFBundleURLTypes`: `yourssh` named "YourSSH URL", `ssh`), `app/lib/mobile/mobile_app.dart` (a `GlobalKey<NavigatorState>` on `MaterialApp`; `MobileLinks(...).attach()` after the first frame), `app/lib/mobile/screens/mobile_add_host_screen.dart` (`prefill` parameter: a new host form seeded with label/host/port/username, saved as a new host), `app/lib/mobile/screens/mobile_settings_screen.dart` (Security group: "Open ssh:// links" switch), `app/lib/mobile/util/mobile_prefs.dart` (`kSshLinksPrefKey`, default false)
- Test: `app/test/mobile/links/mobile_links_test.dart`, `app/test/mobile/links/ssh_link_test.dart`

**Interfaces:**
- Consumes (unchanged): `CliServer({handlers, token, ready, onUrlRefused})`, `CliServer.dedupeWindow`, `UrlChannel(server:, channel:)` + `attach()`, `kUrlMethodChannel`, `CliHandlers`, `resolveHost(query, hosts, allowAdHoc:)` + `ResolvedHost`/`AmbiguousHost`/`AdHocTarget`/`UnknownHost`, `linkRefusedNotification(url, reason)`, `generateToken()` / `sanitize()` from `yourssh_cli`, `openMobileSession` (Task 2), `HostProvider.ready`, `KnownHostsProvider.ready`, `KeyProvider.ready`.
- Produces:
  - `class MobileCliHandlers implements CliHandlers` — `MobileCliHandlers({required HostProvider hostProvider, required Future<void> Function(Host host, String source) open, required String appVersion})`; `connect` → `open(host, source)`; `connectAdHoc` throws `StateError` (URLs never allow ad-hoc); `focusWindow` is a no-op
  - `class MobileLinks` — `MobileLinks({required MobileBootstrap bootstrap, required GlobalKey<NavigatorState> navigator, required String appVersion, MethodChannel urlChannel = kUrlMethodChannel, MethodChannel sshChannel = kSshUrlChannel})` with `void attach()`: one `CliServer(handlers: MobileCliHandlers(open: (h, s) => openMobileSession(nav, h, auditSource: s, resetStack: true)), token: generateToken() /* never written anywhere */, ready: Future.wait([hostProvider.ready, knownHosts.ready, keyProvider.ready]), onUrlRefused: (url, reason) { final n = linkRefusedNotification(url, reason); AppSnack.error(ctx, '${n.title} — ${n.body}'); })`, `UrlChannel(server: …, channel: urlChannel).attach()`, and the `ssh` channel handler + its `ready`
  - `const MethodChannel kSshUrlChannel = MethodChannel('yourssh/ssh_url')`
  - `class SshLinkTarget { final String user; final String host; final int port; String get query; }` and `SshLinkTarget? parseSshLink(String url)` — accepts only `ssh://user@host[:port]` with an optional trailing `/`: no password, no `;` parameters, no other path, no query/fragment, ≤ 2048 chars, user/host/port by the resolver's rules (user `[A-Za-z0-9._-]+`, host DNS/IPv4/`[IPv6]`, port 1–65535, neither starting with `-`)
  - `class SshLinkHandler` — `SshLinkHandler({required List<Host> Function() hosts, required Future<bool> Function() enabled, required Future<void> Function(Host host) openSaved, required Future<bool> Function(SshLinkTarget t) confirm, required void Function(Host prefill) addHost, required void Function(String message) refused, DateTime Function() now = DateTime.now})` with `Future<void> handle(String url)`: off → refused("ssh:// links are off (Settings › Security)"); unparsable → refused; `resolveHost(t.query, hosts(), allowAdHoc: true)`: `ResolvedHost` → `openSaved`, `AmbiguousHost`/`UnknownHost` → refused, `AdHocTarget` → `confirm` (`showYsConfirm` showing `sanitize`d `user@host:port`) → `addHost(Host(label: 'user@host', host:, port:, username:))`; a repeat of the same URL (case-insensitive) within `CliServer.dedupeWindow` is ignored

- [ ] **Step 1: Write the failing tests**

```dart
// mobile_links_test.dart — drive the real CliServer through UrlChannel with a
// mocked 'yourssh/url' channel (see app/test/services/cli/url_channel_test.dart)
test('yourssh://connect opens a saved host by label (NFC, any case)', () async {
  /* host label 'Prod-DB' -> open('yourssh://connect/prod-db') -> opened ['Prod-DB:url'] */
});
test('unknown, ambiguous and unsupported links open nothing and are refused',
    () async {
  for (final u in ['yourssh://connect/nope', 'yourssh://connect/db' /* 'DB' + 'db' */,
      'yourssh://tunnel/start/x', 'yourssh://connect/a?cmd=id',
      'yourssh://u@connect/a', 'yourssh://connect/${'a' * 5000}']) { /* ... */ }
  expect(opened, isEmpty);
  expect(refused, hasLength(6));
  expect(refused.any((m) => m.contains('‮') || m.contains('\x1b')), isFalse);
});
test('the same link twice within 2 s opens once', () async { /* ... */ });

// ssh_link_test.dart
test('parseSshLink accepts user@host[:port] and nothing else', () {
  final t = parseSshLink('ssh://alice@10.0.0.5:2222')!;
  expect([t.user, t.host, t.port], ['alice', '10.0.0.5', 2222]);
  expect(parseSshLink('ssh://alice@[fe80::1]/')!.port, 22);
  for (final u in ['ssh://10.0.0.5', 'ssh://a:pw@h', 'ssh://a;fingerprint=x@h',
      'ssh://a@h/path', 'ssh://a@h?x=1', 'ssh://a@h#f', 'ssh://-oProxyCommand=x@h',
      'ssh://a@-h', 'ssh://a@h:0', 'ssh://a@h:70000',
      'ssh://a@${'h' * 3000}', 'yourssh://connect/a']) {
    expect(parseSshLink(u), isNull, reason: u);
  }
});
test('ssh:// is refused while the setting is off', () async { /* enabled false */ });
test('ssh:// to a saved user@host:port opens that host', () async { /* openSaved */ });
test('ssh:// to an unknown target asks first and only prefills Add Host',
    () async {
  /* confirm false -> nothing; confirm true -> addHost(Host(username: 'alice',
     host: '203.0.113.7', port: 22)); openSaved never called */
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/mobile/links`
Expected: FAIL with "MobileLinks isn't defined". (**Local**)

- [ ] **Step 3: Implement the signatures.** No new URL parser for `yourssh://`: everything goes through `CliServer` (`connect/<one segment>` only, id then label, saved hosts only, refused → `onUrlRefused`, audit source `url`). `openMobileSession` refuses RDP/VNC hosts (Task 2). A link that arrives while the app is locked opens its route under the lock (Task 6) and is revealed on unlock.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile test/services/cli && flutter analyze --no-fatal-infos && bash ../tool/check_ui_lint.sh`
Expected: PASS (**Local**; the desktop CLI tests stay green). On a simulator, warm and cold: `xcrun simctl openurl booted "yourssh://connect/<label>"` opens the session; `xcrun simctl openurl booted "ssh://demo@203.0.113.7"` (setting on) asks, then shows a prefilled Add Host (**Manual**).

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile app/ios app/test/mobile/links
git commit -m "feat: yourssh:// and opt-in ssh:// links on iOS through CliServer"
```

### Task 12: Bundle exclusion check and iOS CI job

**Files:**
- Create: `tool/check_ios_bundle.sh` (arg: path to a `.app`; POSIX tools only; fails, listing offenders, if any file or directory name matches `qjsbridge|libquickjs|yourssh_rdp|yourssh_vnc|flutter_pty`, if any file contains the bytes `pty_forkpty` (`grep -a -r -l`), or if the bundle's `Info.plist` contains `NSAllowsArbitraryLoads`), `app/integration_test/ios_smoke_test.dart` (pumps `YourSSHMobileApp` with `app_lock_enabled = false`, adds a host through `HostProvider`, finds its card on the hosts tab, opens Settings; no network)
- Modify: `.github/workflows/pr-test.yml` (new `ios` job; add it to the aggregate `test` job's `needs`, its echo line and its checks)
- Test: `app/test/tooling/check_ios_bundle_test.dart`

**Interfaces:**
- Produces: job `ios` on `macos-latest`, `timeout-minutes: 45`, using pr-test's pinned actions (`actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7`, `subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2` with `${{ env.FLUTTER_VERSION }}`): `flutter pub get`; `flutter test test/mobile test/platform test/util` (Darwin paths such as `chmodNative`); `flutter build ios --simulator --no-codesign`; `flutter build ios --release --no-codesign` + `bash tool/check_ios_bundle.sh app/build/ios/iphoneos/Runner.app`; boot the first available iPhone simulator (`xcrun simctl list devices available --json`, pick an `iPhone` on the newest iOS runtime, `xcrun simctl boot`) and run `flutter test integration_test/ios_smoke_test.dart -d <udid>`. The full unit suite keeps running on ubuntu in the `app` job.

- [ ] **Step 1: Write the failing test**

```dart
Future<ProcessResult> check(String dir) =>
    Process.run('bash', ['../tool/check_ios_bundle.sh', dir]);
test('rejects a bundle containing the QuickJS bridge', () async {
  final d = Directory.systemTemp.createTempSync();
  File('${d.path}/Frameworks/libqjsbridge.dylib').createSync(recursive: true);
  expect((await check(d.path)).exitCode, isNot(0));
});
test('rejects a binary carrying the PTY fork symbol', () async {
  final d = Directory.systemTemp.createTempSync();
  File('${d.path}/Frameworks/X.framework/X')
    ..createSync(recursive: true)
    ..writeAsBytesSync([0, ...'_pty_forkpty'.codeUnits, 0]);
  expect((await check(d.path)).exitCode, isNot(0));
});
test('accepts a clean bundle', () async {
  final d = Directory.systemTemp.createTempSync();
  File('${d.path}/Runner').createSync();
  File('${d.path}/Info.plist').writeAsStringSync('<plist></plist>');
  expect((await check(d.path)).exitCode, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tooling/check_ios_bundle_test.dart`
Expected: FAIL (script missing). (**Local**)

- [ ] **Step 3: Implement the script, the smoke test and the workflow job.** The `test` aggregate must stay red unless `ios` is green (`[ "${{ needs.ios.result }}" = "success" ] || exit 1`).

- [ ] **Step 4: Run the test and the script on a real build**

Run: `cd app && flutter test test/tooling && flutter build ios --release --no-codesign && bash ../tool/check_ios_bundle.sh build/ios/iphoneos/Runner.app && (command -v actionlint >/dev/null && actionlint ../.github/workflows/pr-test.yml || true)`
Expected: PASS and exit 0 (**Local**). The simulator smoke test runs only in the `ios` job (**CI-only**: no simulator runtime locally); check it is green on the PR.

- [ ] **Step 5: Commit**

```bash
git add tool/check_ios_bundle.sh .github/workflows/pr-test.yml app/test/tooling app/integration_test/ios_smoke_test.dart
git commit -m "ci: iOS build, bundle exclusion check and simulator smoke test in pr-test"
```

### Task 13: Signed IPA and TestFlight upload in release.yml

**Files:**
- Modify: `.github/workflows/release.yml` (new `build-ios` job, `needs: test`, `runs-on: macos-latest`, release.yml's pinned actions: `actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4`, `subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2`)
- Create: `app/ios/ExportOptions.plist` (`method` = `app-store-connect`, `teamID` = `84T567KMYD`, `signingStyle` = `manual`, `provisioningProfiles` = { `com.thangnm.yourssh`: profile name }, `uploadSymbols` = true)
- Test: `app/test/tooling/release_ios_job_test.dart`

**Interfaces:**
- Secrets (job env `IOS_SIGNING: ${{ secrets.IOS_DISTRIBUTION_P12_BASE64 != '' && secrets.IOS_PROVISIONING_PROFILE_BASE64 != '' && secrets.ASC_KEY_ID != '' && secrets.ASC_ISSUER_ID != '' && secrets.ASC_API_KEY_P8_BASE64 != '' }}`, documented in a comment like `MACOS_SIGNING`): `IOS_DISTRIBUTION_P12_BASE64`, `IOS_DISTRIBUTION_P12_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`. Unset → `flutter build ios --release --no-codesign --split-debug-info=build/symbols`, bundle check, artifact; no signing or upload.
- Signed steps: import the Apple Distribution identity into a temporary keychain (same commands as the macOS "Import Developer ID certificate" step, matching `Apple Distribution` instead of `Developer ID Application`, exporting `SIGN_KEYCHAIN`), install the profile (`~/Library/MobileDevice/Provisioning Profiles/<UUID>.mobileprovision`, UUID read with `security cms -D`), `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist --build-number=${{ github.run_number }} --split-debug-info=build/symbols` (manual signing applies to the Runner target only — set it in the Runner target's Release settings or the export options, never on the command line, which would also hit the SPM/CocoaPods targets), `bash tool/check_ios_bundle.sh app/build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app`, write `AuthKey_$ASC_KEY_ID.p8` under `$RUNNER_TEMP/private_keys` and upload with `xcrun altool --upload-app -f <ipa> -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"` (`API_PRIVATE_KEYS_DIR` set), or `xcodebuild -exportArchive` with `destination = upload` if the runner's Xcode no longer ships that `altool` mode; then the IPA and a symbols zip as workflow artifacts. The `release` job's `needs` list is NOT extended (iOS goes to TestFlight, not to the GitHub release page).

- [ ] **Step 1: Write the failing test** (workflow text assertions)

```dart
String job(String y, String name) {
  final start = y.indexOf('\n  $name:');
  final next = RegExp(r'\n  [a-z][a-z0-9-]*:\n').firstMatch(y.substring(start + 1));
  return next == null ? y.substring(start) : y.substring(start, start + 1 + next.start);
}
test('release.yml has a gated build-ios job that stays off the GitHub release',
    () {
  final y = File('../.github/workflows/release.yml').readAsStringSync();
  final ios = job(y, 'build-ios');
  expect(ios, contains('needs: test'));
  expect(ios, contains('IOS_SIGNING:'));
  expect(ios, contains("if: env.IOS_SIGNING == 'true'"));
  expect(ios, contains('check_ios_bundle.sh'));
  expect(ios, contains('ASC_KEY_ID'));
  expect(ios, contains('if: always()'));
  expect(job(y, 'release'), isNot(contains('build-ios')));
  final opts = File('ios/ExportOptions.plist').readAsStringSync();
  expect(opts, allOf(contains('84T567KMYD'), contains('app-store-connect')));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/tooling/release_ios_job_test.dart`
Expected: FAIL (`build-ios:` missing). (**Local**)

- [ ] **Step 3: Add the job and `ExportOptions.plist`.** Secrets are only read inside steps with `if: env.IOS_SIGNING == 'true'`; never echo them; delete the temporary keychain, the profile and `AuthKey_*.p8` in an `if: always()` step.

- [ ] **Step 4: Run test, then validate the workflow**

Run: `cd app && flutter test test/tooling/release_ios_job_test.dart && (command -v actionlint >/dev/null && actionlint ../.github/workflows/release.yml || true)`
Expected: PASS; actionlint reports no errors if installed (**Local**). The first real upload needs the repo secrets and an App Store Connect record for `com.thangnm.yourssh` under team `84T567KMYD` (**CI-only**, on a push to `master`); read the App Store Connect processing email for ITMS-90683/91053 warnings and fix them in Task 10's files.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml app/ios/ExportOptions.plist app/test/tooling/release_ios_job_test.dart
git commit -m "ci: signed iOS IPA and TestFlight upload gated on secrets"
```

### Task 14: Documentation

**Files:**
- Modify: `CLAUDE.md` (Architecture intro: the app also targets Android and iOS through `app/lib/mobile`; a short **iOS** section: UIScene runner + `YourSshNative` channels `yourssh/url`, `yourssh/ssh_url`, `yourssh/background`, `yourssh/files`; `MobileLifecycleCoordinator` grace/pause/resume; keys in backup-excluded Application Support; `iosKeychainOptions` and no plaintext fallback; links through `CliServer`/`UrlChannel`; `tool/check_ios_bundle.sh` and the pr-test `ios` job; the local build commands and that no simulator runtime is assumed), `CHANGELOG.md` (`[Unreleased]` → Added: iOS (iPhone) TestFlight build; Fixed: the mobile app lock now covers pushed screens; RDP/VNC hosts show a "desktop only" notice on mobile; imported keys are copied into app storage), `README.md` (platform list)
- Test: none (docs only)

- [ ] **Step 1: Update the three files**, matching their existing style (CLAUDE.md keeps file/symbol names exact).

- [ ] **Step 2: Check nothing else moved**

Run: `git diff --stat` and `cd app && flutter test test/platform`
Expected: only the three docs files changed; tests PASS (**Local**).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md CHANGELOG.md README.md
git commit -m "docs: document the iOS build"
```

## Self-Review

- Spec coverage: flags (T1), desktop-only guards incl. the CLI lock/update/sandbox paths and RDP/VNC hosts (T2, T12), UIScene runner, iPhone family, min iOS, ML Kit-free scanner (T3), UI on iPhone (T4), Keychain + no plaintext fallback (T5), lock above all routes + Face ID (T6), tmux default + no-subprocess key generation (T7), background grace/pause/reconnect (T8), keys/Files/share/backup exclusion (T9), usage strings/encryption/privacy manifest, no ATS (T10), `yourssh://` via `CliServer` + opt-in `ssh://` (T11), bundle check + simulator CI (T12), TestFlight (T13), docs (T14). iPad, hardware keyboard, Secure Enclave, `yourssh://sftp`, App Store submission, RDP/VNC, mosh, App Intents are phase 2/3 and deliberately absent.
- Type consistency: `isIOSPlatform`/`supportsRemoteDesktop`/`supportsSubprocesses`/`mobileDefaultTmux` (T1) are used in T2, T5, T7, T9; `openMobileSession`/`canOpenOnMobile` (T2) are reused by T11; `chmodNative`/`ChmodFn` (T7) by T9; `SshSession.paused`/`acceptsInput` (T8) are the only new session members; `AppPaths` (T9) is the sole mobile key-directory source; `YourSshNative` (T3) gains channels in T8, T9, T11; `CliServer`/`UrlChannel`/`resolveHost` are consumed unchanged.
- Verification: every task's test step is **Local**; launching and simulator flows are **Manual** or **CI-only** (T12 smoke test, T13 upload), as the owner's Mac has no simulator runtime.
- Proportion: signatures and assertions only; Swift bodies and workflow YAML are left to the builder per the spec.
