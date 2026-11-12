# YourSSH for iOS (iPhone + iPad) — design

Date: 2026-11-12 · Status: proposed (owner skipped Q&A and delegated the decisions below)

## Intent

YourSSH already runs on Android from the same Flutter codebase: `main()` branches on `isMobilePlatform` (`app/lib/platform/runtime_platform.dart`, which already treats `TargetPlatform.iOS` as mobile) and mounts `YourSSHMobileApp` (`app/lib/mobile/`, 39 files: hosts, terminal + accessory key bar, SFTP, snippets, keys, sync, QR import, app lock, TOFU watcher). The same app on iPhone/iPad reaches the many users who administer servers from an Apple device, without a second codebase. The work is mostly platform plumbing (runner, Keychain, lifecycle, files, store compliance) rather than new UI.

## Goals

1. Ship the existing mobile UI on iPhone (iOS 16+) through TestFlight, then the App Store; iPad layouts follow in phase 2.
2. Parity with the Android preview: hosts list/search/tags, terminal with accessory key bar (sticky Ctrl/Alt, arrows, Esc, Tab) and pinch zoom, single-panel SFTP, snippets, key generate/import, port forwarding while foreground, cloud sync + P2P QR import, biometric app lock, TOFU host keys + known hosts.
3. Behave correctly under iOS suspension: sessions are visibly paused, resume on foreground, and shell state survives via tmux.
4. Pass App Review on the first submission (see risk list).

## Non-goals

- Local shell (iOS has no PTY / `fork`), JS plugins, RDP/VNC (phase 3), session recordings, audit log (desktop only for now).
- Keeping sockets alive in the background by any trick (VoIP push, location, audio).
- A separate iOS-only UI kit; the mobile theme/widgets are reused.
- Paid features, IAP or subscriptions (the app is free).

## Anti-goals (a failure even if it "works")

- Rejected by App Review for downloaded executable code (guideline 2.5.2): no QuickJS engine reachable, no native lib for it in the bundle, no plugin download/marketplace UI.
- Secrets (passwords, passphrases, private keys, sync code) leaving the device: not in iCloud Keychain, iCloud/iTunes backup, the Files app, logs, or URLs.
- A paused/reconnecting session silently losing or silently replaying typed input.
- A `yourssh://` or `ssh://` link able to connect to an attacker-chosen host without an explicit confirmation, or to run commands.
- Face ID lock re-prompting in a loop or being bypassable via the app-switcher snapshot.

## Constraints

- Same Flutter codebase; new `app/ios`; bundle id `com.thangnm.yourssh`, display name `YourSSH`, minimum iOS 16, Apple team `84T567KMYD` (SENPRINTS LLC, the team already used for Developer ID).
- Flutter is pinned to 3.47.1 in CI (`FLUTTER_VERSION` in `.github/workflows/pr-test.yml` / `release.yml`); a developer machine on 3.50 must not be required.
- `supabase_flutter` is held at 2.12.x (passkeys pull in a newer Darwin floor, see `app/pubspec.yaml`); iOS 16 is compatible, do not bump it here.
- iOS suspends the app about 30 s after backgrounding; `beginBackgroundTask` grants only the remainder of a short grace period.
- `Process.run` of external binaries is unavailable (no `ssh-keygen`, no `tmux` locally).
- Several packages in `app/pubspec.yaml` have no iOS implementation (`window_manager`, `hotkey_manager`, `local_notifier`): Flutter simply does not register them on iOS, as on Android; they must not be referenced on the mobile path.

## Decisions (owner-delegated, with rationale)

| Decision | Rationale |
|---|---|
| One codebase, add `app/ios`, reuse `app/lib/mobile` | Android already proves the mobile UI; avoids a fork. |
| iPhone first, iPad in phase 2 | iPad needs sidebar/split/multi-window work that is independent of getting a store-ready build. |
| v1 scope = Android-preview parity | Known, tested surface (`app/test/mobile/`). |
| No local shell: guard `flutter_pty` | `forkpty`/`fork()` are prohibited on iOS. |
| No JS plugins: exclude QuickJS | Guideline 2.5.2 forbids downloaded executable code. |
| RDP/VNC deferred to phase 3 | Needs Rust `aarch64-apple-ios` (+ simulator) targets and an XCFramework. |
| Recordings/audit desktop-only | Not in the Android preview either; avoids sqlite/App Privacy scope. |
| Suspend model: `beginBackgroundTask`, mark sessions paused, auto-reconnect on foreground, tmux auto-attach ON by default on mobile | Honest about iOS limits; tmux keeps shell state server-side. No VoIP/location tricks (review rejection). |
| Mosh-style roaming in phase 3 | Real fix for suspension, but a protocol project of its own. |
| Secrets in Keychain via `flutter_secure_storage`, `first_unlock_this_device`, not synchronizable; Face ID via `local_auth` | Keeps secrets off iCloud; background reconnect needs access after first unlock. |
| Files: SFTP downloads to app Documents (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`), share sheet to export, document picker to import keys | Matches iOS file model; no directory picker. |
| Usage strings: camera, Face ID, local network; privacy manifest | Required for review and for the P2P QR import. |
| URL scheme `yourssh://` (same semantics as the desktop CLI spec, saved hosts only) + optional `ssh://` | Reuses an already reviewed security model. |
| Phase 2: iPad, hardware keyboard, Secure Enclave P-256 keys, App Store submission. Phase 3: RDP/VNC, mosh, Shortcuts/App Intents, widgets | Ordered by value/risk. |
| Distribution: TestFlight, then App Store, team `84T567KMYD`; CI: unsigned simulator build + tests in pr-test; signed IPA + TestFlight upload in release.yml via App Store Connect API key, gated on secrets | Mirrors macOS signing steps. |
| Export compliance: declare encryption use (`ITSAppUsesNonExemptEncryption = YES`), rely on the mass-market exemption for standard SSH crypto, file the annual self-classification report (owned by the company admin, not the builder) | Owner approved the recommendation; SSH/AES-GCM implemented in-app is non-exempt-by-default, so it must be declared. |
| The app is free (no IAP/subscriptions in scope) and ships under the company team `84T567KMYD` (SENPRINTS LLC), bundle id `com.thangnm.yourssh`, App Store Connect record under that team | Owner answer. |

## App Review risk list

| Risk | Mitigation |
|---|---|
| 2.5.2 downloaded code | No plugin loader instantiated on mobile (`MobileBootstrap` never builds `ScriptEngineService`); no QuickJS dylib in the bundle (the engine loads `libqjsbridge.dylib` only on macOS paths and has no plugin native code); CI asserts the bundle has no `qjsbridge`, `yourssh_rdp`, `yourssh_vnc`, `flutter_pty` binary. |
| `fork()`/PTY symbols | `flutter_pty` fork drops its `ios:` platform entry (see Architecture). |
| Export compliance (non-exempt crypto) | `ITSAppUsesNonExemptEncryption = YES` in Info.plist and matching App Store Connect answers; mass-market exemption for standard SSH crypto; annual self-classification report filed by the company admin. |
| Privacy manifest / required-reason APIs | `PrivacyInfo.xcprivacy` (UserDefaults `CA92.1`, file timestamps `C617.1`, system boot time `35F9.1` only if used) plus each pod's own manifest; no tracking. |
| Local network prompt | `NSLocalNetworkUsageDescription`; Bonjour services only if LAN discovery ships. |
| Camera/Face ID strings | Plain-language `NSCameraUsageDescription`, `NSFaceIDUsageDescription`. |
| ATS | The P2P import fetches `http://<lan-ip>:<port>` (AES-GCM payload, key in the QR): needs `NSAppTransportSecurity` → `NSAllowsLocalNetworking`, no global `NSAllowsArbitraryLoads`. |
| 4.2 minimum functionality / "terminal apps" | Same category as existing SSH clients; reviewer notes explain a demo host. |
| Account-less login | App has no accounts; cloud sync uses a sync code, no Sign in with Apple required. |

## Architecture

### Platform guards

Add capability flags to `app/lib/platform/runtime_platform.dart` (keep `defaultTargetPlatform`, so tests override them with `debugDefaultTargetPlatformOverride`):

- `isIOSPlatform`
- `supportsLocalShell` = `!isMobilePlatform`
- `supportsJsPlugins` = `!isMobilePlatform`
- `supportsRemoteDesktop` = `!isMobilePlatform` until phase 3
- `mobileDefaultTmux` = `isMobilePlatform`

`main()` already routes mobile to `YourSSHMobileApp`; nothing under `app/lib/mobile` may import `main_screen.dart`, `plugin_*`, `local_shell_service.dart`, `recording_*` or `audit_*`. Platform-specific behavior inside shared files (`StorageService`, `KeyGenService`, `SettingsProvider`, `SessionProvider`) is gated by these flags, never by raw `Platform.isIOS`, except native-channel code.

### Excluded packages and how

| Package | Reality in the repo | iOS handling |
|---|---|---|
| `flutter_pty` (local fork, `packages/flutter_pty`) | pubspec declares `ios: ffiPlugin: true` and `src/forkpty.c` calls `fork()` | Remove the `ios:` entry from the fork's `plugin.platforms` so CocoaPods never compiles it; Dart still imports it (as on desktop), `DynamicLibrary` loading is lazy; `LocalShellService` is never constructed on mobile (`supportsLocalShell`). |
| `yourssh_script_engine` | No `flutter: plugin:`; `quickjs_ffi.dart` loads `libqjsbridge.dylib` from macOS paths only (throws `UnsupportedError` elsewhere, lazily); `HookBus` is imported by `ssh_service.dart` and `share_session_service.dart` | No native lib is bundled. Not instantiated on mobile. Bundle check in CI. `HookBus` stays (pure Dart, no code loading). |
| `yourssh_rdp`, `yourssh_vnc` | Dart-only on iOS; Rust dylibs loaded by `native_loader.dart` on macOS/Linux/Windows paths; imported by `session_provider.dart` | No native lib built for iOS in phase 1; RDP/VNC entry points hidden by `supportsRemoteDesktop`; `reconnectRdp/Vnc` unreachable. |
| `window_manager`, `hotkey_manager`, `local_notifier` | No iOS platform in the packages; only referenced from the desktop path | Not registered by Flutter on iOS; no change. |
| `sqlite3_flutter_libs` | Used by `audit_service.dart` only | Keep (builds on iOS); audit not wired on mobile. |
| `webview_flutter` | Monaco editor screen is desktop/SFTP-edit only | Not reachable from the mobile screens in phase 1. |

If a future review objects to unreachable Dart code, split `HookBus` out of the engine package; not needed for phase 1.

### Secrets

`StorageService` currently passes only `mOptions`/`wOptions` to `FlutterSecureStorage`; add `iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device, synchronizable: false)` (and the same on `AiChatProvider`). Private keys imported on mobile live under Application Support (not Documents), excluded from backup (`NSURLIsExcludedFromBackupKey`), mode 0600. Because `UIFileSharingEnabled` exposes the Documents directory in Files, the existing `getApplicationDocumentsDirectory()/YourSSH/keys` in `mobile_keys_screen.dart` must move.

### Suspension lifecycle

New `MobileLifecycleCoordinator` (observer on `WidgetsBinding`) plus a `MethodChannel('com.thangnm.yourssh/background')` implemented in `AppDelegate.swift` (`begin` → task id, `end(id)`):

1. `inactive`/`paused`: start a background task; flush in-flight SFTP transfers or fail them cleanly; stop port-forward accepting; mark every connected `SshSession` `SessionStatus.paused`; end the task before expiry (expiration handler also ends it).
2. `resumed`: after Face ID unlock (if the lock gate is up), reconnect paused sessions with the existing `SessionProvider` auto-reconnect path, staggered; restart forwards that were running.
3. Input while not `connected` is rejected visibly (banner "Session paused — reconnecting"); it is never buffered and replayed into a new shell.
4. tmux auto-attach defaults ON on mobile (`SettingsProvider.tmuxEnabled` is `false` by default today and shared with desktop, so the mobile default is applied at first launch only, user choice wins); if tmux is missing on the server the session falls back to a plain shell with a notice.

### Files, links, permissions

- SFTP download writes to `<Documents>/Downloads/` via `safeLocalChild`; share sheet for export; `FilePicker.pickFiles` (document picker) for key and upload import; the directory picker used by `_download` today is removed on iOS.
- `Info.plist`: `CFBundleURLTypes` (`yourssh`, optional `ssh`), `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, usage strings, ATS local-networking exception, `ITSAppUsesNonExemptEncryption` = true, `UIRequiresFullScreen` unset.
- URL router (`app/lib/mobile/links/url_router.dart`): same semantics as `docs/superpowers/specs/2026-11-12-yourssh-cli-design.md` (on branch `feature/cli`, not yet in `develop`) — `yourssh://connect/<id-or-label>` and `yourssh://sftp/<id-or-label>?path=…`, saved hosts only; `ssh://` for an unknown host shows a confirmation sheet with the target and never auto-connects. The CLI server itself is desktop only and is not a dependency.

### Key generation

`KeyGenService` shells out to `ssh-keygen` for RSA/ECDSA; `generateEd25519` is pure Dart. On iOS only Ed25519 is offered (the screen already hides the others when `probeSshKeygen()` is false). Secure Enclave P-256 keys come in phase 2.

### P2P / LAN

Mobile only scans the QR and fetches from the desktop's one-shot server, so no Bonjour browsing is needed in phase 1; `NetworkDiscoveryService` (mDNS) is not on the mobile path. Local-network permission is requested by the first LAN fetch, with `NSLocalNetworkUsageDescription` explaining it.

## Phasing

- **Phase 1 (this plan):** runner and build, guards and exclusions, mobile UI on iPhone, Keychain + Face ID, background pause/reconnect/tmux, Files/picker/share, usage strings + privacy manifest, URL scheme, simulator build/tests in CI, signed TestFlight upload.
- **Phase 2:** iPad (split view/sidebar, Stage Manager multi-window via UIScene), hardware keyboard (Cmd shortcuts, Cmd+. → Esc, Caps-as-Ctrl option), Secure Enclave non-exportable ECDSA P-256 keys, App Store submission.
- **Phase 3:** RDP/VNC (Rust `aarch64-apple-ios` targets), mosh/roaming, Shortcuts/App Intents (connect, run snippet), widgets.

## Decided here

- The capability flag names above and their values.
- Input is rejected (not buffered) while a session is not connected.
- Only Ed25519 key generation in phase 1.
- Keys move to Application Support; Documents holds only user-visible downloads.
- Free app, company team `84T567KMYD`, bundle id `com.thangnm.yourssh`.
- `ITSAppUsesNonExemptEncryption = YES`; the annual self-classification filing is the company admin's job.
- `flutter_pty` is excluded by editing the fork's pubspec, not by `dependency_overrides` swaps.

## Left to the builder

- Swift details of the background-task channel and `AppDelegate` URL handling (or `app_links`/`uni_links`, if a package is preferred; note it in the PR).
- Exact stagger/backoff for foreground reconnects, within the existing reconnect settings.
- Icon asset catalog generation (extend `tool/gen_app_icons.py`) and launch screen.
- Fastlane vs. plain `xcodebuild` + `xcrun altool`/`xcrun notarytool` for the TestFlight upload.
- Whether the privacy manifest needs the system-boot-time reason after the final dependency list.

## Open owner questions

None. The owner decided: free app (no IAP/subscriptions), company team `84T567KMYD` (SENPRINTS LLC), and export compliance as above (declare encryption, mass-market exemption, annual self-classification report filed by the company admin).
