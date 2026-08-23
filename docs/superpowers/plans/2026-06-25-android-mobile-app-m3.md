# Android Mobile App — Milestone 3 (Sync import) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Android, import hosts from the desktop — pull from Supabase cloud sync, and scan a desktop's P2P QR code with the camera.

**Architecture:** Reuse the existing sync stack unchanged — `SyncProvider`/`SyncService` (cloud), `P2PSyncService`/`P2PSyncEncryption` + `SyncService.parsePayload` (P2P) — and apply results through the existing `HostProvider.replaceAll(hosts, passwords)`, exactly as desktop does. M3.1 adds cloud pull (no new dependency). M3.2 adds camera QR scanning, which requires a new `mobile_scanner` dependency and the Android camera permission.

**Tech Stack:** Flutter, `provider`, existing sync services, `mobile_scanner` (new, M3.2).

## Global Constraints

- Dart package `yourssh`; dark-only (`AppColors`); reuse existing classes; don't modify desktop bootstrap/widgets.
- Mobile is a sync **consumer** (pull/receive only) — no push from mobile.
- Cloud apply and P2P apply both go through `HostProvider.replaceAll` (replaces all hosts — same semantics as desktop import).
- Desktop builds + full `flutter test` + `flutter analyze` MUST stay green.
- No Claude attribution. Commit after each task. Branch `feat/android-mobile-app`.

## Key existing APIs (verified)

- `SyncProvider({StorageService? storage})` auto-loads in ctor; `setSupabaseConfig(url, anonKey)`, `setSyncCode(value)`, getters `supabaseUrl`/`supabaseAnonKey`/`syncCode`/`enabled`/`status` (`SyncStatus.{idle,syncing,synced,error}`)/`error`, `isSupabaseConfigured`, `hasSyncCode`.
- `SyncService(SyncProvider)`; `Future<SyncPayload?> pull()` (returns null when disabled/no-change/error; sets provider status).
- `HostProvider.replaceAll(List<Host> hosts, Map<String,String> passwords)`.
- P2P transfer code is JSON `{"u": "<url>", "k": "<base64 key>"}`. `P2PSyncService().fetchPayload(url) → Future<String>` (encrypted); `P2PSyncEncryption.decrypt(encrypted, List<int> key) → Future<String>`; `SyncService.parsePayload(decrypted) → SyncPayload`.
- `SyncCode.length == 12`.

---

## Phase M3.1 — Cloud sync pull (no new dependency)

### Task 1: Add SyncProvider + SyncService to the mobile bootstrap

**Files:**
- Modify: `app/lib/mobile/mobile_bootstrap.dart`
- Test: `app/test/mobile/mobile_bootstrap_test.dart` (extend)

**Interfaces:**
- Produces: `MobileBootstrap.sync` (SyncProvider) and `MobileBootstrap.syncService` (SyncService); both added to `providers` (SyncProvider as ChangeNotifier, SyncService as plain Provider).

- [ ] **Step 1: Extend the bootstrap test**

Add to `app/test/mobile/mobile_bootstrap_test.dart` inside `main()`:
```dart
  test('exposes sync provider + service', () {
    final b = MobileBootstrap();
    expect(b.sync, isNotNull);
    expect(b.syncService, isNotNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_bootstrap_test.dart`
Expected: FAIL — `sync`/`syncService` getters undefined.

- [ ] **Step 3: Add to the bootstrap**

In `app/lib/mobile/mobile_bootstrap.dart`, add imports:
```dart
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
```
Add fields + construction (after `knownHosts`):
```dart
  late final SyncProvider sync;
  late final SyncService syncService;
```
In the constructor body (after `knownHosts = ...`):
```dart
    sync = SyncProvider(storage: storage);
    syncService = SyncService(sync);
```
Add to the `providers` getter list:
```dart
        ChangeNotifierProvider.value(value: sync),
        Provider.value(value: syncService),
```

- [ ] **Step 4: Run test + analyze**

Run: `cd app && flutter test test/mobile/mobile_bootstrap_test.dart && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/mobile_bootstrap.dart app/test/mobile/mobile_bootstrap_test.dart
git commit -m "feat(mobile): add sync provider + service to bootstrap"
```

---

### Task 2: Settings screen with Cloud Sync section + Pull

**Files:**
- Create: `app/lib/mobile/screens/mobile_settings_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (index 3 → settings screen)
- Test: `app/test/mobile/mobile_settings_screen_test.dart`

**Interfaces:**
- Consumes: `SyncProvider` (config getters + `setSupabaseConfig`/`setSyncCode`), `SyncService.pull()`, `HostProvider.replaceAll`.
- Produces: `class MobileSettingsScreen extends StatefulWidget` — Cloud Sync card (URL / anon key / sync code fields seeded from the provider, Save persists via `setSupabaseConfig` + `setSyncCode`, "Pull from cloud" runs `pull()` → `replaceAll` → SnackBar with count or the provider error). P2P entry is added in M3.2.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_settings_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_settings_screen.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/sync_service.dart';

Future<void> _pump(WidgetTester tester, SyncProvider sync) async {
  final storage = StorageService();
  await tester.pumpWidget(MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider(create: (_) => HostProvider(storage)),
        Provider<SyncService>(create: (_) => SyncService(sync)),
      ],
      child: const MobileSettingsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saving cloud config writes to the provider', (tester) async {
    final sync = SyncProvider();
    await _pump(tester, sync);

    await tester.enterText(
        find.byKey(const Key('sync-url')), 'https://x.supabase.co');
    await tester.enterText(find.byKey(const Key('sync-anon')), 'anon-key-123');
    await tester.enterText(
        find.byKey(const Key('sync-code')), '123456789012');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(sync.supabaseUrl, 'https://x.supabase.co');
    expect(sync.supabaseAnonKey, 'anon-key-123');
    expect(sync.syncCode, '123456789012');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_settings_screen_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/screens/mobile_settings_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/host_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';

/// Settings tab. M3 ships the Sync section (cloud pull; P2P scan added in
/// M3.2). Appearance + app-lock arrive in M5.
class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({super.key});

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  final _url = TextEditingController();
  final _anon = TextEditingController();
  final _code = TextEditingController();
  bool _seeded = false;
  bool _pulling = false;

  @override
  void dispose() {
    _url.dispose();
    _anon.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    if (!_seeded) {
      _url.text = sync.supabaseUrl;
      _anon.text = sync.supabaseAnonKey;
      _code.text = sync.syncCode;
      _seeded = true;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
          backgroundColor: AppColors.bg, title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Cloud Sync',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Pull hosts from your desktop via Supabase.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            _field(_url, 'Supabase URL', 'sync-url'),
            _field(_anon, 'Anon key', 'sync-anon'),
            _field(_code, 'Sync code (12 chars)', 'sync-code'),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(onPressed: _save, child: const Text('Save')),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _pulling ? null : _pull,
                  child: _pulling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Pull from cloud'),
                ),
              ],
            ),
            if (sync.error != null) ...[
              const SizedBox(height: 10),
              Text(sync.error!,
                  style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final sync = context.read<SyncProvider>();
    await sync.setSupabaseConfig(_url.text, _anon.text);
    await sync.setSyncCode(_code.text);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sync settings saved')));
    }
  }

  Future<void> _pull() async {
    setState(() => _pulling = true);
    final payload = await context.read<SyncService>().pull();
    if (!mounted) return;
    if (payload != null) {
      await context
          .read<HostProvider>()
          .replaceAll(payload.hosts, payload.passwords);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Imported ${payload.hosts.length} hosts from cloud')));
      }
    } else if (mounted) {
      final err = context.read<SyncProvider>().error;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Nothing new to pull')));
    }
    if (mounted) setState(() => _pulling = false);
  }

  Widget _field(TextEditingController c, String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: Key(key),
        controller: c,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire into the shell (index 3)**

In `app/lib/mobile/screens/mobile_home_shell.dart`, import `mobile_settings_screen.dart` and change the `_body()` switch: add `case 3: return const MobileSettingsScreen();` (keep SFTP at 2 as the placeholder). The `default` now only covers index 2.

- [ ] **Step 5: Run tests + analyze**

Run: `cd app && flutter test test/mobile/ && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/mobile/screens/mobile_settings_screen.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/mobile_settings_screen_test.dart
git commit -m "feat(mobile): settings screen with cloud sync pull"
```

---

## Phase M3.2 — P2P QR camera import (adds mobile_scanner)

### Task 3: Transfer-code parser (pure)

**Files:**
- Create: `app/lib/mobile/sync/transfer_code.dart`
- Test: `app/test/mobile/transfer_code_test.dart`

**Interfaces:**
- Produces: `({String url, List<int> key}) parseTransferCode(String raw)` — decodes the `{"u","k"}` JSON; throws `FormatException` on missing/blank fields or bad base64. Used by the QR scan screen so the network/decrypt steps run on validated input.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/transfer_code_test.dart`:
```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/sync/transfer_code.dart';

void main() {
  test('parses a valid transfer code', () {
    final key = List<int>.generate(32, (i) => i);
    final raw = jsonEncode({'u': 'http://192.168.1.5:8080/sync', 'k': base64.encode(key)});
    final parsed = parseTransferCode(raw);
    expect(parsed.url, 'http://192.168.1.5:8080/sync');
    expect(parsed.key, key);
  });

  test('throws on missing fields', () {
    expect(() => parseTransferCode('{"u":"http://x"}'), throwsFormatException);
    expect(() => parseTransferCode('not json'), throwsFormatException);
    expect(() => parseTransferCode('{"u":"","k":"AAAA"}'), throwsFormatException);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/transfer_code_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/sync/transfer_code.dart`:
```dart
import 'dart:convert';

/// Parses a P2P transfer code (the JSON encoded in the desktop's QR / export
/// string: `{"u": "<url>", "k": "<base64 key>"}`). Throws [FormatException]
/// on malformed input so the caller can show a clear "invalid code" error.
({String url, List<int> key}) parseTransferCode(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw.trim());
  } catch (_) {
    throw const FormatException('Not a valid transfer code');
  }
  if (decoded is! Map) throw const FormatException('Not a transfer code');
  final url = decoded['u'];
  final k = decoded['k'];
  if (url is! String || url.isEmpty || k is! String || k.isEmpty) {
    throw const FormatException('Transfer code is missing fields');
  }
  final List<int> key;
  try {
    key = base64.decode(k);
  } catch (_) {
    throw const FormatException('Transfer code key is invalid');
  }
  return (url: url, key: key);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/transfer_code_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/sync/transfer_code.dart app/test/mobile/transfer_code_test.dart
git commit -m "feat(mobile): P2P transfer-code parser"
```

---

### Task 4: Add mobile_scanner dependency + Android camera permission

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: `mobile_scanner` available for import; `<uses-permission android:name="android.permission.CAMERA"/>` declared.

- [ ] **Step 1: Add the dependency**

In `app/pubspec.yaml` dependencies, add (a recent stable line):
```yaml
  mobile_scanner: ^5.2.3
```
Run: `cd app && flutter pub get`
Expected: resolves successfully. (If `^5.2.3` doesn't resolve against the pinned Flutter SDK, run `flutter pub add mobile_scanner` and accept whatever compatible version it picks.)

- [ ] **Step 2: Add the camera permission**

In `app/android/app/src/main/AndroidManifest.xml`, add inside `<manifest>` (before `<application>`):
```xml
    <uses-permission android:name="android.permission.CAMERA"/>
```

- [ ] **Step 3: Analyze**

Run: `cd app && flutter analyze lib/mobile`
Expected: `No issues found!` (no usages yet, just the dep present).

- [ ] **Step 4: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/android/app/src/main/AndroidManifest.xml
git commit -m "build(mobile): add mobile_scanner + camera permission"
```

---

### Task 5: QR scan screen + P2P import flow + Settings entry

**Files:**
- Create: `app/lib/mobile/screens/mobile_qr_scan_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_settings_screen.dart` (add P2P section with a "Scan QR code" button)
- Test: manual (camera) — logic covered by Task 3's parser test.

**Interfaces:**
- Consumes: `parseTransferCode`, `P2PSyncService.fetchPayload`, `P2PSyncEncryption.decrypt`, `SyncService.parsePayload`, `HostProvider.replaceAll`.
- Produces: `class MobileQrScanScreen extends StatefulWidget` — full-screen `MobileScanner`; on the first detected barcode, runs the import flow once (guarded), pops with a result, and the caller shows a SnackBar.

- [ ] **Step 1: Write the scan screen**

Create `app/lib/mobile/screens/mobile_qr_scan_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/host_provider.dart';
import '../../services/p2p_sync_encryption.dart';
import '../../services/p2p_sync_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../sync/transfer_code.dart';

/// Full-screen camera QR scanner for P2P host import. On the first valid code
/// it fetches + decrypts the payload from the exporting device and replaces
/// the local host list, then pops `true` (imported count via SnackBar in the
/// caller). Pops with an error string on failure.
class MobileQrScanScreen extends StatefulWidget {
  const MobileQrScanScreen({super.key});

  @override
  State<MobileQrScanScreen> createState() => _MobileQrScanScreenState();
}

class _MobileQrScanScreenState extends State<MobileQrScanScreen> {
  final _p2p = P2PSyncService();
  bool _handled = false;

  @override
  void dispose() {
    _p2p.stop();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    _handled = true;
    try {
      final code = parseTransferCode(raw);
      final encrypted = await _p2p.fetchPayload(code.url);
      final decrypted = await P2PSyncEncryption.decrypt(encrypted, code.key);
      final payload = SyncService.parsePayload(decrypted);
      if (payload.hosts.isEmpty) {
        throw const FormatException('No hosts in transfer');
      }
      if (!mounted) return;
      await context
          .read<HostProvider>()
          .replaceAll(payload.hosts, payload.passwords);
      if (mounted) Navigator.of(context).pop('Imported ${payload.hosts.length} hosts');
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(
            'Import failed: ${e.toString().replaceFirst('FormatException: ', '')}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: AppColors.bg, title: const Text('Scan transfer QR')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
```

> Verify at execution: `mobile_scanner` v5 exposes `MobileScanner(onDetect:)` and `BarcodeCapture.barcodes` (List<Barcode> with `.rawValue`). If the installed major version differs, adjust the callback signature accordingly. `firstOrNull` needs `package:collection` OR use `capture.barcodes.isEmpty ? null : capture.barcodes.first`.

- [ ] **Step 2: Add the P2P section + scan button to Settings**

In `mobile_settings_screen.dart`, add below the Cloud Sync section a P2P block:
```dart
            const SizedBox(height: 24),
            const Text('P2P transfer',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Scan the QR code shown on your desktop (Settings → Sync → Show QR).',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
              onPressed: _scan,
            ),
```
And add the `_scan` method (uses a push to the scan screen + SnackBar on result):
```dart
  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MobileQrScanScreen()),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }
```
Add the import: `import 'mobile_qr_scan_screen.dart';`

- [ ] **Step 3: Analyze + mobile tests**

Run: `cd app && flutter analyze lib/mobile && flutter test test/mobile/`
Expected: `No issues found!`; tests PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/mobile/screens/mobile_qr_scan_screen.dart app/lib/mobile/screens/mobile_settings_screen.dart
git commit -m "feat(mobile): P2P QR camera import"
```

---

### Task 6: Build + regression

**Files:** none (verification)

- [ ] **Step 1: Full test suite**

Run: `cd app && flutter test`
Expected: all tests pass.

- [ ] **Step 2: Analyze whole repo**

Run: `cd app && flutter analyze`
Expected: no NEW issues (the 2 pre-existing `integration_test` probe warnings may remain).

- [ ] **Step 3: Build the APK (confirms mobile_scanner builds for Android)**

Run: `cd app && flutter build apk --debug`
Expected: `✓ Built ... app-debug.apk`. If mobile_scanner bumps `minSdkVersion`, set it in `android/app/build.gradle.kts` and re-run.

- [ ] **Step 4: Restore any regenerated desktop registrants**

Run (keep the branch free of pub-get registrant churn):
```bash
git checkout HEAD -- app/macos/Flutter/GeneratedPluginRegistrant.swift app/windows/flutter/generated_plugin_registrant.cc app/windows/flutter/generated_plugins.cmake 2>/dev/null || true
```

- [ ] **Step 5: On-device (user, when a device/emulator is available)**

Manual: Settings → enter Supabase config → Pull → hosts appear in Hosts tab; OR Settings → Scan QR (grant camera) → point at desktop QR → hosts imported.

---

## Self-Review

**Spec coverage (M3):**
- "Cloud Supabase sync import" → Tasks 1, 2 (pull → replaceAll). ✓
- "P2P QR sync" (scan from desktop) → Tasks 3, 4, 5. ✓
- "pull hosts from desktop" → both apply via `HostProvider.replaceAll`. ✓

**Placeholder scan:** No vague steps; code complete. The two `> Verify at execution` notes (mobile_scanner version API, `firstOrNull`) name concrete fallbacks.

**Type consistency:** `MobileBootstrap.sync`/`syncService` (Task 1) used in Settings test wiring (Task 2). `parseTransferCode` return shape `({String url, List<int> key})` (Task 3) consumed in the scan screen (Task 5). `replaceAll(hosts, passwords)` used identically in cloud (Task 2) and P2P (Task 5) paths.

## Deferred

- Mobile→desktop push (mobile stays a consumer).
- TOFU mismatch dialog, appearance, app-lock → M5. SFTP, snippets/history → M4.
