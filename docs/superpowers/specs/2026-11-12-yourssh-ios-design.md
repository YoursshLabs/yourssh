# YourSSH for iOS (iPhone + iPad) — design

Date: 2026-11-12 · Refreshed 2026-11-13 against `develop` @ `8c6f0cd1` (the 0.4.0 feature set: forui redesign, `yourssh` CLI and `yourssh://` links, Flutter 3.50) · Status: proposed (owner skipped Q&A and delegated the decisions below)

## Intent

YourSSH already runs on Android from the same Flutter codebase: `main()` branches on `isMobilePlatform` (`app/lib/platform/runtime_platform.dart`, which already treats `TargetPlatform.iOS` as mobile) and mounts `YourSSHMobileApp` (`app/lib/mobile/`, 42 files: hosts, terminal + accessory key bar, SFTP, snippets, keys, port forwards, sync, QR import and LAN pairing, app lock, TOFU watcher), rebuilt on forui with touch sizing (`ysThemeDataTouch()` / `ysRootBuilderTouch`). The same app on iPhone/iPad reaches the many users who administer servers from an Apple device, without a second codebase. The work is mostly platform plumbing (runner, Keychain, lifecycle, files, store compliance) rather than new UI.

## Goals

1. Ship the existing mobile UI on iPhone (iOS 16+) through TestFlight, then the App Store; iPad layouts follow in phase 2.
2. Parity with the Android preview: hosts list/search/tags, terminal with accessory key bar (sticky Ctrl/Alt, arrows, Esc, Tab) and pinch zoom, single-panel SFTP, snippets, key generate/import, port forwarding while foreground, cloud sync + LAN QR import and pairing, biometric app lock, TOFU host keys + known hosts.
3. Behave correctly under iOS suspension: short app switches keep sessions, longer ones pause them visibly, they resume on foreground, and shell state survives via tmux.
4. Pass App Review on the first submission (see risk list).

## Non-goals

- Local shell (iOS has no PTY / `fork`), JS plugins, RDP/VNC (phase 3), session recordings, audit log (desktop only for now).
- Desktop-only infrastructure: the CLI socket/pipe listener and the single-instance lock (`app/lib/services/cli/single_instance.dart`, `cli_listener*.dart`), the in-app updater (`UpdateService`/`UpdateProvider`, desktop installers only — iOS updates come from the App Store), the macOS sandbox migration and the plaintext-secret migration (an iOS install has no earlier plaintext secrets).
- `yourssh://sftp/...` links: the CLI spec puts them in its phase 2 and `CliServer` does not accept them yet; iOS gets them when `CliServer` does.
- Keeping sockets alive in the background by any trick (VoIP push, location, audio).
- A separate iOS-only UI kit; the mobile forui theme/widgets are reused.
- Paid features, IAP or subscriptions (the app is free).

## Anti-goals (a failure even if it "works")

- Rejected by App Review for downloaded executable code (guideline 2.5.2): no QuickJS engine reachable, no native lib for it in the bundle, no plugin download/marketplace UI.
- Secrets (passwords, passphrases, private keys, sync code) leaving the device: not in iCloud Keychain, iCloud/device backup (this includes `UserDefaults`, so no plaintext fallback), the Files app, logs, or URLs.
- A paused/reconnecting session silently losing or silently replaying typed input.
- A `yourssh://` or `ssh://` link able to connect to an attacker-chosen host without an explicit confirmation, or to run commands.
- Face ID lock re-prompting in a loop, being bypassable via the app-switcher snapshot, or leaving a pushed screen (terminal, SFTP) visible above the lock.

## Constraints

- Same Flutter codebase; new `app/ios`; bundle id `com.thangnm.yourssh`, display name `YourSSH`, minimum iOS 16, Apple team `84T567KMYD` (SENPRINTS LLC, the team already used for Developer ID). Phase 1 targets iPhone only (`TARGETED_DEVICE_FAMILY = 1`; iPads run it in iPhone compatibility mode).
- Flutter is pinned to **3.50.0** in CI (`FLUTTER_VERSION` in `.github/workflows/pr-test.yml` and `release.yml`, kept equal; see CLAUDE.md "Toolchain"). The iOS work uses that version; bumping Flutter also means bumping the Android toolchain and is a separate change.
- Flutter 3.50's iOS template uses the **UIScene lifecycle** (`AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate` + `SceneDelegate: FlutterSceneDelegate`, `UIApplicationSceneManifest` in `Info.plist`). Native code registers through `didInitializeImplicitFlutterEngine` and receives URL opens as scene events (`scene(_:openURLContexts:)`, cold start via `scene(_:willConnectTo:options:)`), not through `application(_:open:options:)`. The iOS 27 SDK requires UIScene adoption.
- Flutter 3.50 resolves plugins through Swift Package Manager where they support it and CocoaPods for the rest (the macOS runner already shows `FlutterGeneratedPluginSwiftPackage`); the iOS project uses both.
- `supabase_flutter` is held at 2.12.x (2.13+ pulls in passkeys, whose Darwin plugin needs macOS 13.5, see `app/pubspec.yaml`); iOS 16 is compatible, do not bump it here.
- iOS suspends the app shortly after backgrounding; `beginBackgroundTask` grants only the remainder of a short grace period (about 30 s).
- No subprocesses: `Process.run` is unavailable on iOS (no `ssh-keygen`, no `chmod` binary, no local `tmux`). Code on the mobile path that shells out today (`KeyGenService.probeSshKeygen`, `chmodLocal` used by `KeyGenService.generateEd25519`) must not run on iOS.
- Several packages in `app/pubspec.yaml` have no iOS implementation (`window_manager`, `hotkey_manager`, `local_notifier`): Flutter does not register them on iOS, as on Android; they are only called on the desktop path of `main()`.
- UI rules (CLAUDE.md "Design system"): new or changed mobile UI uses forui widgets / `Ys*` components and `YsColors` tokens (not `MobileColors`, which is deprecated), toasts via `AppSnack`/`showYsToast` (lifted above `MobileTabBar` by `ysRootBuilderTouch`), dialogs via `showYsDialog`/`showYsConfirm`, sheets via `showFSheet`, icons from `FLucideIcons`, touch `FItem`s ≥ 44 px. `tool/check_ui_lint.sh` (the `ui` job in pr-test) applies to `app/lib`: no `IconButton(`, `AlertDialog(`, `SnackBar(`, `Icons.`, `ScaffoldMessenger`, `showDialog(`, `showModalBottomSheet`, `TextField(`; no `Color(0x…)` literals in widgets.
- Local environment (owner's Mac): Xcode 27.2 with the iOS 27.2 SDK and CocoaPods 1.17, but **no simulator runtime** (`xcrun simctl list runtimes` is empty). Locally: `flutter build ios --simulator --no-codesign` and `flutter build ios --release --no-codesign` plus every `flutter test`; launching on a simulator and simulator integration tests are CI-only (macOS runner) or need a device.

## Decisions (owner-delegated, with rationale)

| Decision | Rationale |
|---|---|
| One codebase, add `app/ios`, reuse `app/lib/mobile` | Android already proves the mobile UI; avoids a fork. |
| iPhone first (`TARGETED_DEVICE_FAMILY = 1`), iPad in phase 2 | iPad needs sidebar/split/multi-window work; shipping the iPad family early would put iPad layouts in front of App Review. |
| v1 scope = Android-preview parity | Known, tested surface (`app/test/mobile/`). |
| No local shell: drop the `flutter_pty` fork's iOS platform | `forkpty`/`fork()` are prohibited on iOS. |
| No JS plugins: QuickJS never loaded or bundled | Guideline 2.5.2 forbids downloaded executable code. |
| RDP/VNC deferred to phase 3; RDP/VNC hosts (synced from desktop) show a "desktop only" notice instead of connecting on mobile | Needs Rust `aarch64-apple-ios` (+ simulator) targets and an XCFramework. Today a tap on such a host on Android creates an error tab the mobile UI never shows. |
| Recordings/audit desktop-only | Not in the Android preview either; avoids sqlite/App Privacy scope. |
| Suspend model: on background, `beginBackgroundTask` and a grace timer (≤ 25 s, inside the OS allowance); sessions keep running during it. When it runs out, port forwards stop and SSH sessions are paused (clients closed cleanly, marked paused, no auto-reconnect, no "dropped" notice). On foreground, paused sessions reconnect staggered through the existing retry path; sessions that stayed "connected" are probed with an SSH keepalive and reconnected if dead. tmux auto-attach ON for fresh mobile installs | A quick app switch (2FA code, copy a token) must not cost a reconnect; a long absence ends in a known paused state instead of half-dead sockets. tmux keeps shell state server-side. No VoIP/location tricks (review rejection). |
| Paused = a `SshSession.paused` flag with status `disconnected`, not a new `SessionStatus` value | `SessionStatus` is switched on in five files (`ssh_session.dart`, `session_health.dart`, `terminal_status_bar.dart`, `session_connecting_view.dart`, `mobile_terminal_screen.dart`), some exhaustively and some through a `_` default that would silently mislabel a new value; a flag keeps the desktop untouched. |
| Mosh-style roaming in phase 3 | Real fix for suspension, but a protocol project of its own. |
| Secrets in the iOS data-protection Keychain via `flutter_secure_storage` `IOSOptions(accessibility: first_unlock_this_device, synchronizable: false)`; **no plaintext fallback on iOS** | Keeps secrets off iCloud and backups; background reconnect needs access after first unlock. The macOS options (`MacOsOptions(useDataProtectionKeyChain: false)`, the legacy-Keychain workaround for ad-hoc signing) do not apply: iOS has only the data-protection Keychain and a signed iOS app has its own access group. A failed Keychain write is an error the user sees, never a write to `UserDefaults` (backed up). |
| App lock sits above the Navigator (`MaterialApp.builder`), keeps the app mounted offstage while locked | Today `AppLockGate` is the `home` route, so a pushed terminal/SFTP route stays on top of the lock screen and in the app-switcher snapshot. |
| Face ID via `local_auth` (existing `AppLockGate`) | Already implemented on Android. |
| Files: SFTP downloads to app Documents/`Downloads` (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`), share sheet to export, document picker to import keys/uploads; picked keys are copied into private storage | Matches iOS file model; no directory picker; the picker's copy lives in a purgeable temp/cache dir. |
| Usage strings: camera, Face ID, local network (SSH to LAN hosts, reachability probe, LAN pairing); privacy manifest | Required for review; local network privacy covers every connection to a LAN address, not only the QR import. |
| No `NSAppTransportSecurity` exceptions | All app networking is `dart:io` (`Socket`, `HttpClient`, `HttpServer`), which ATS does not cover; dart:io on Flutter 3.50 has no insecure-HTTP policy left (`_EmbedderConfig` only carries `_mayExit`). |
| QR scanner without Google ML Kit on iOS: upgrade `mobile_scanner` to the release line whose iOS backend is Apple Vision (no `GoogleMLKit` pod) if 5.x is still the locked version when the runner is added | ML Kit adds a large binary, its own data-collection disclosures for App Privacy, and historically no arm64-simulator slice (the simulator build would not link on Apple silicon). |
| URL scheme `yourssh://connect/<id-or-label>` handled by the **existing** `CliServer` + `UrlChannel` (`app/lib/services/cli/`) with a mobile `CliHandlers`; the iOS native side implements the same `yourssh/url` channel contract as `MainFlutterWindow.swift` (`open` / `ready`, newest 8 queued). Optional `ssh://user@host[:port]` (Settings toggle, default off) resolves through `resolveHost`; a saved host opens like `yourssh://`, an unknown target opens a confirmation, then the Add Host screen prefilled — never a connection | One reviewed model: saved hosts only, id then label (NFC, case-insensitive, trimmed), ambiguity refused, same-URL 2 s debounce, sanitized refusal notice (`linkRefusedNotification`, shown as a toast — mobile has no bell). An ad-hoc connect would need agent auth, which iOS lacks. |
| No subprocesses on iOS: Ed25519 only, file modes set through libc `chmod` over `dart:ffi` | `Process.run` is unavailable; Ed25519 is pure Dart. |
| Phase 2: iPad, hardware keyboard, Secure Enclave P-256 keys, App Store submission (with iPhone screenshots from `integration_test/mobile_screenshots_test.dart` on a simulator). Phase 3: RDP/VNC, mosh, Shortcuts/App Intents, widgets | Ordered by value/risk. |
| Distribution: TestFlight, then App Store, team `84T567KMYD`; CI: simulator build + bundle check + simulator smoke test in pr-test (macOS runner); signed IPA + TestFlight upload in release.yml via App Store Connect API key, gated on secrets | Mirrors the macOS signing steps (`MACOS_SIGNING` gate, temporary keychain). |
| Export compliance: declare encryption use (`ITSAppUsesNonExemptEncryption = YES`), rely on the mass-market exemption for standard SSH crypto, file the annual self-classification report (owned by the company admin, not the builder) | Owner approved the recommendation; SSH/AES-GCM implemented in-app is non-exempt-by-default, so it must be declared. |
| The app is free (no IAP/subscriptions in scope) and ships under the company team `84T567KMYD` (SENPRINTS LLC), bundle id `com.thangnm.yourssh`, App Store Connect record under that team | Owner answer. |

## App Review risk list

| Risk | Mitigation |
|---|---|
| 2.5.2 downloaded code | `ScriptEngineService` and `PluginLoader` (with `reservedIds`) are built only in `main.dart`'s desktop state; `MobileBootstrap` builds neither, and a test keeps `app/lib/mobile` from importing them. `quickjs_ffi.dart` opens `libqjsbridge.dylib` only on macOS (a lazy top-level `lib`; `UnsupportedError` elsewhere) and the package bundles no assets. The bundled JS Snippets plugin and `MigrationBridge` are gone, so there is no plugin directory to seed. CI asserts the bundle has no `qjsbridge`, `yourssh_rdp`, `yourssh_vnc`, `flutter_pty` file and no `pty_forkpty` symbol. |
| `fork()`/PTY symbols | The `flutter_pty` fork drops its `ios:` platform entry (see Architecture). |
| Export compliance (non-exempt crypto) | `ITSAppUsesNonExemptEncryption = YES` in Info.plist and matching App Store Connect answers; mass-market exemption for standard SSH crypto; annual self-classification report filed by the company admin. |
| Privacy manifest / required-reason APIs | `PrivacyInfo.xcprivacy` (UserDefaults `CA92.1`, file timestamps `C617.1`, system boot time `35F9.1` only if used) plus each pod/package's own manifest; no tracking; App Privacy "Data Not Collected" holds only without ML Kit (see Decisions). |
| Missing purpose strings for APIs a plugin links (ITMS-90683, e.g. photo library from `file_picker`'s media picker) | Prefer the plugin's documented build flags that compile the unused picker out; otherwise a plain-language string. Decided from the first upload's validation result. |
| Local network prompt | `NSLocalNetworkUsageDescription` naming SSH to local servers and LAN host import; Bonjour services only if LAN discovery ships (it does not in phase 1). The prompt can appear on the hosts screen because `HostReachabilityProbe` dials saved hosts. |
| Camera/Face ID strings | Plain-language `NSCameraUsageDescription`, `NSFaceIDUsageDescription`. |
| ATS | No exceptions (dart:io networking is outside ATS); a test asserts `NSAllowsArbitraryLoads` is absent. |
| 4.2 minimum functionality / "terminal apps" | Same category as existing SSH clients; reviewer notes explain a demo host. |
| iPad review of an iPhone-only build | Runs in compatibility mode; phase 1 layouts are phone layouts by design. |
| Account-less login | App has no accounts; cloud sync uses a sync code, no Sign in with Apple required. |

## Architecture

### Platform guards

Add capability flags to `app/lib/platform/runtime_platform.dart` (keep `defaultTargetPlatform`, so tests override them with `debugDefaultTargetPlatformOverride`). Only flags with a consumer in phase 1:

- `isIOSPlatform`
- `supportsRemoteDesktop` = `!isMobilePlatform` until phase 3 (mobile host open / links)
- `supportsSubprocesses` = `!isIOSPlatform` (`KeyGenService`)
- `mobileDefaultTmux` = `isMobilePlatform` (`SettingsProvider` first-run default)

`main()` routes mobile to `YourSSHMobileApp` and returns **before** `claimSingleInstance`, the sandbox migration, `window_manager`, `hotkey_manager` and `NotificationService.init` — so iOS never takes the CLI lock, opens a socket/pipe or writes `cli.token`. `migratePlaintextSecrets`, the update check, plugins, audit and recordings live in the desktop `_YourSSHAppState` and never run on mobile. Nothing under `app/lib/mobile` may import `main.dart`, `screens/main_screen.dart`, `services/cli/single_instance.dart`, `services/cli/cli_listener*.dart`, `services/cli/peer_cred.dart`, `services/cli/app_cli_handlers.dart`, `services/update_service.dart`, `providers/update_provider.dart`, `services/local_shell_service.dart`, `services/pty_runner.dart`, `recording_*`, `audit_*`, `plugin_*`, `yourssh_script_engine`, `window_manager`, `hotkey_manager` or `local_notifier` (guard test). `services/cli/cli_server.dart`, `url_channel.dart`, `host_resolver.dart`, `cli_handlers.dart` and `link_refused.dart` are allowed: they are the shared URL semantics. Platform-specific behavior inside shared files (`StorageService`, `KeyGenService`, `SettingsProvider`, `SessionProvider`) is gated by these flags, never by raw `Platform.isIOS`, except native-channel code.

### Excluded packages and how

| Package | Reality in the repo | iOS handling |
|---|---|---|
| `flutter_pty` (local fork, `packages/flutter_pty`) | `pubspec.yaml` declares `ios: ffiPlugin: true` (and ships `ios/flutter_pty.podspec`); `src/forkpty.c` calls `fork()` | Remove the `ios:` entry from the fork's `flutter.plugin.platforms`, so neither CocoaPods nor SPM builds it; Dart still imports it via `session_provider.dart` → `local_shell_service.dart` (the `DynamicLibrary` is opened lazily); `SessionProvider.localShell` stays null on mobile (`MobileBootstrap` never sets it). |
| `yourssh_script_engine` | No `flutter: plugin:` and no assets; `quickjs_ffi.dart` loads `libqjsbridge.dylib` from macOS paths only; `HookBus` is imported by `ssh_service.dart` and `share_session_service.dart` | No native lib is bundled. Not instantiated on mobile. Bundle check in CI. `HookBus` stays (pure Dart, no code loading). |
| `yourssh_rdp`, `yourssh_vnc` | Dart packages, no Flutter plugin; Rust libs loaded by `NativeLoader` on desktop paths; imported by `session_provider.dart` | No native lib built for iOS in phase 1; mobile host open and links refuse RDP/VNC hosts (`supportsRemoteDesktop`), so `connectRdp`/`connectVnc` are unreachable. |
| `window_manager`, `hotkey_manager`, `local_notifier` | No iOS platform; only called on the desktop path | Not registered by Flutter on iOS; no change. |
| `yourssh_cli` (pure Dart) | Imported by `cli_server.dart` for the protocol types; its socket/pipe/launcher code is only used by the desktop listener and the CLI binary | Compiled in for `CliRequest`/`CliResponse`/`generateToken`/`sanitize`; no endpoint code runs on iOS. |
| `sqlite3_flutter_libs` | Used by `audit_service.dart` only | Keep (builds on iOS); audit not wired on mobile. |
| `webview_flutter` | Monaco editor screen is desktop/SFTP-edit only | Not reachable from the mobile screens in phase 1. |
| `mobile_scanner` 5.2.3 | iOS podspec depends on `GoogleMLKit/BarcodeScanning ~> 6.0.0` | Upgrade to the Apple Vision line before the first iOS build (see Decisions); Android re-verified by the pr-test `android` job. |

If a future review objects to unreachable Dart code, split `HookBus` out of the engine package; not needed for phase 1.

### Secrets

`StorageService` passes only `mOptions`/`wOptions` to `FlutterSecureStorage` today; add `iOptions: StorageService.iosKeychainOptions` = `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device, synchronizable: false)` (default account name). `AiChatProvider` is desktop-only (not in `MobileBootstrap`) and is left unchanged. On iOS, `StorageService(allowPlaintextFallback: false)` (wired by `MobileBootstrap`): a failed secure write throws `SecretStoreException` instead of writing `UserDefaults`; the mobile screens that save secrets (host add/edit, key passphrase, sync code, QR/cloud import) show it as an error toast. Consequences accepted: `ThisDeviceOnly` items and the backup-excluded key directory are not restored to a new phone from a backup — users move hosts with the sync code or LAN pairing, which carries passwords.

Private keys generated or imported on mobile live under `<Application Support>/keys` (not Documents), the directory excluded from backup (`NSURLIsExcludedFromBackupKey`, set natively), files 0600. Because `UIFileSharingEnabled` exposes the Documents directory in Files, `mobile_keys_screen.dart`'s `getApplicationDocumentsDirectory()/YourSSH/keys` must move. Imported keys are **copied** there from the document picker's temporary copy (which `KeyProvider.addKeyFromFile` registers by path today, so the key breaks when iOS purges it), then the picker's temporary files are cleared. There is no legacy migration: iOS has no earlier install, and Android's Documents directory is app-private (existing Android keys stay put).

### App lock

`AppLockGate` moves from `MaterialApp.home` into `MaterialApp.builder` (inside `ysRootBuilderTouch`, so the lock screen keeps the forui theme): it wraps the Navigator, so every route and dialog is covered. While locked the Navigator stays mounted but `Offstage` with tickers off (not painted, no hit testing, no semantics), so routes, in-flight connects and TOFU prompts survive an unlock. It still locks on `inactive`/`hidden`/`paused` (app-switcher snapshot) and ignores the transitions its own biometric sheet causes (`_authInFlight`); an unenrolled device falls open as on Android.

### Suspension lifecycle

`MobileLifecycleCoordinator` (`app/lib/mobile/lifecycle/`, iOS only in phase 1; Android keeps today's behavior) listens to `AppLifecycleState` and uses a `yourssh/background` method channel (`begin` → `{id, remaining}` from `UIApplication.beginBackgroundTask(withName:expirationHandler:)` and `backgroundTimeRemaining`; `end(id)`):

1. `paused` (app backgrounded; `inactive` is ignored — Face ID sheet, Control Center, app switcher): begin a background task and start a grace timer of `min(remaining − 5 s, 25 s)`. Sessions keep running.
2. Grace timer fires: record which port forwards run and stop them (`PortForwardService.stopAll`, before closing clients so its 2–30 s reconnect backoff never starts); `SessionProvider.pauseAll()` marks every connected or reconnecting SSH session `paused` (status `disconnected`), cancels its reconnect timers, writes a dim `[Paused while YourSSH was in the background]` line and closes each affected host's client once (`SshService.disconnect`); `_doConnect` sees `paused` and returns without scheduling a reconnect or firing `onSessionDropped`. Then end the task. The Swift expiration handler also ends it.
3. `resumed`: cancel the grace timer and end the task if still open; `resumePaused(stagger)` calls the existing `reconnectSession(id)` for each paused session in tab order, 300 ms apart (regardless of the auto-reconnect setting: a pause is app-initiated, not a drop; `reconnectSession` honors `tmuxEnabled` and the retry settings); `verifyLive()` pings each host that still has a "connected" session (`SshService.isAlive`, keepalive with a 3 s timeout) and pauses + reconnects the dead ones; then restart the recorded forwards. Reconnecting does not wait for the lock gate: the gate hides the UI, not the network.
4. Input while not connected is rejected visibly: the terminal body mounts `TerminalView` only for `connected` (the paused state shows "Session paused — reconnecting"), `SshService.sendInput` returns false without buffering, and the snippet and side-panel insert paths say "Session is not connected" when it does. Nothing is buffered or replayed into a new shell.
5. tmux auto-attach is ON for fresh mobile installs: `SettingsProvider.tmuxEnabled` is `false` by default and shared with desktop, so when no `tmuxEnabled` pref exists a mobile install without saved hosts stores `true` (the same once-only pattern as the `terminalTheme` default); existing Android installs keep `false`. Mobile Settings gains a "Keep sessions in tmux" switch, so the user choice wins. With tmux on, `openShell` types `tmux new-session -A -s yourssh`; a server without tmux prints its own "command not found" and stays a plain shell.

### Native side (UIScene)

One Swift class, `YourSshNative` (`app/ios/Runner/YourSshNative.swift`, a `FlutterPlugin` + `FlutterSceneLifeCycleDelegate`), registered in `AppDelegate.didInitializeImplicitFlutterEngine` with `engineBridge.pluginRegistry.registrar(forPlugin: "YourSshNative")` and `registrar.addSceneDelegate(...)`. It owns the method channels:

- `yourssh/url` — same contract as macOS `MainFlutterWindow.swift`: native → Dart `open(String)` for `yourssh://` URLs from `scene(_:openURLContexts:)` and the cold-start `connectionOptions.urlContexts`; Dart → native `ready` flushes the queue (newest 8 kept).
- `yourssh/ssh_url` — the same contract for `ssh://` URLs (a separate channel so `UrlChannel` is reused unchanged).
- `yourssh/background` — `begin` / `end` (above).
- `yourssh/files` — `excludeFromBackup(path)` (`URLResourceValues.isExcludedFromBackup`).

### Files, links, permissions

- SFTP download writes to `<Documents>/Downloads/` via `safeLocalChild` (never overwriting: `name (1).ext`), streamed to a `.part` file renamed on success and deleted on failure; a toast action opens the share sheet (`share_plus`); `FilePicker.pickFiles` (document picker) for uploads and key import, followed by `FilePicker.platform.clearTemporaryFiles()`; the directory picker `_download` uses today stays on Android only.
- `Info.plist`: `CFBundleURLTypes` (`yourssh`, `ssh`), `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, usage strings, `ITSAppUsesNonExemptEncryption` = true, no ATS keys, `UIRequiresFullScreen` unset, the template's `UIApplicationSceneManifest`.
- `yourssh://`: `app/lib/mobile/links/mobile_links.dart` builds one `CliServer` (`handlers: MobileCliHandlers`, `token: generateToken()` — never written anywhere, the trusted path skips it; `ready` = hosts + known hosts + keys loaded; `onUrlRefused` → error toast built from `linkRefusedNotification`) and attaches `UrlChannel(server: …)`. So the iOS link semantics are exactly the desktop ones: `yourssh://connect/<one segment>` only (no query, fragment, userinfo, port), id then label (NFC, case-insensitive, trimmed), ambiguous → refused, saved hosts only (`allowAdHoc: false`), same URL within 2 s ignored, `connect` audit source `url`. `MobileCliHandlers.connect` opens the session through the same `openMobileSession` the hosts screen uses (RDP/VNC → "desktop only" toast); `connectAdHoc` is unreachable for URLs and throws; `focusWindow` is a no-op (iOS already foregrounded the app).
- `ssh://`: off until the user enables "Open ssh:// links" in mobile Settings (a refused link says so). Accepted shape `ssh://user@host[:port]` with an optional trailing `/` — no password, no `;fingerprint` parameters, no query/fragment, ≤ 2048 chars; `user@host[:port]` goes through `resolveHost(…, allowAdHoc: true)`: `ResolvedHost` → same as `yourssh://connect`; `AmbiguousHost`/`UnknownHost` → refused toast; `AdHocTarget` → `showYsConfirm` showing the exact target (sanitized) → `MobileAddHostScreen(prefill: …)`; nothing connects until the user saves the host and opens it. Same-URL 2 s debounce.

### Key generation

`KeyGenService` shells out to `ssh-keygen` for RSA/ECDSA and to `chmod` for the private key's mode; `generateEd25519` is otherwise pure Dart. On iOS (`!supportsSubprocesses`) `probeSshKeygen()` returns false without spawning anything and `MobileBootstrap` injects `chmodNative` (libc `chmod` through `dart:ffi`; `mode_t` is `uint16` on Darwin) as the service's `chmod`; the keys screen builds its algorithm list from `supportedAlgorithms()`, so only Ed25519 is offered. Secure Enclave P-256 keys come in phase 2.

### P2P / LAN

Mobile both receives (QR scan → `P2PSyncService.fetchPayload`, private-address URLs only) and sends ("Pair new device": `getLocalInterfaces()` + a one-shot `HttpServer` while the screen is open). Both use `dart:io`, no Bonjour, so no `NSBonjourServices` in phase 1; `NetworkDiscoveryService` (mDNS) is not on the mobile path. Local-network permission is requested by the first LAN connection (often `HostReachabilityProbe` dialing a LAN host on the hosts screen, or an SSH connect), with `NSLocalNetworkUsageDescription` explaining it. The pairing server only works in the foreground; a background pause closes it.

## Phasing

- **Phase 1 (this plan):** runner and build (UIScene), guards and exclusions, mobile UI on iPhone, Keychain + Face ID + lock above all routes, background grace/pause/reconnect/tmux, Files/picker/share, usage strings + privacy manifest, `yourssh://connect` + optional `ssh://`, simulator build/tests in CI, signed TestFlight upload.
- **Phase 2:** iPad (`TARGETED_DEVICE_FAMILY = 1,2`, split view/sidebar, Stage Manager multi-window via `UIApplicationSupportsMultipleScenes`), hardware keyboard (Cmd shortcuts, Cmd+. → Esc, Caps-as-Ctrl option), Secure Enclave non-exportable ECDSA P-256 keys, `yourssh://sftp` once `CliServer` accepts it, App Store submission with simulator screenshots.
- **Phase 3:** RDP/VNC (Rust `aarch64-apple-ios` targets), mosh/roaming, Shortcuts/App Intents (connect, run snippet), widgets.

## Decided here

- The capability flags above (only those with a phase-1 consumer) and their values.
- Input is rejected (not buffered) while a session is not connected; paused is a flag, not a `SessionStatus` value.
- Background: a grace window of at most 25 s before pausing; resume reconnects paused sessions regardless of the auto-reconnect setting and probes the rest.
- tmux default ON only for fresh mobile installs; a mobile Settings switch for it.
- Only Ed25519 key generation in phase 1; no subprocesses on iOS.
- Keys live in backup-excluded Application Support; Documents holds only user-visible downloads; imported keys are copied in.
- No plaintext secret fallback on iOS.
- The app lock wraps the Navigator.
- `yourssh://` reuses `CliServer`/`UrlChannel`; `ssh://` is opt-in and never connects to an unknown target (prefilled Add Host after confirmation).
- No ATS exceptions; iPhone-only device family.
- Free app, company team `84T567KMYD`, bundle id `com.thangnm.yourssh`.
- `ITSAppUsesNonExemptEncryption = YES`; the annual self-classification filing is the company admin's job.
- `flutter_pty` is excluded by editing the fork's pubspec, not by `dependency_overrides` swaps.

## Left to the builder

- Swift details of `YourSshNative` (channels above, scene URL handling).
- Exact stagger/backoff for foreground reconnects, within the existing reconnect settings.
- Icon asset catalog generation (extend `tool/gen_app_icons.py`) and launch screen.
- Fastlane vs. plain `xcodebuild` + `xcrun altool` (or `xcodebuild -exportArchive` with `destination = upload`) for the TestFlight upload — whatever the runner's Xcode supports.
- Whether the privacy manifest needs the system-boot-time reason after the final dependency list, and how to clear any ITMS-90683 purpose-string warning (plugin build flags preferred).
- The exact `mobile_scanner` version (the newest whose iOS backend has no `GoogleMLKit` pod and that still builds the Android APK).

## Open owner questions

None. The owner decided: free app (no IAP/subscriptions), company team `84T567KMYD` (SENPRINTS LLC), and export compliance as above (declare encryption, mass-market exemption, annual self-classification report filed by the company admin).
