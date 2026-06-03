# In-App Update (Assisted Download) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify the user inside the app when a newer stable GitHub release exists, then download the correct artifact for their OS/arch and hand off to the OS installer (assisted download — no silent self-replace).

**Architecture:** A Flutter-free `UpdateService` talks to the GitHub `releases/latest` API, compares semver, picks the matching asset, downloads it, and launches the OS installer. An `UpdateProvider` (ChangeNotifier) drives a debounced launch check + manual check, holds the state machine, and feeds a dismissible banner in `MainScreen` plus an "Updates" section in Settings.

**Tech Stack:** Flutter, `provider`, `http` (+ `http/testing.dart` MockClient for tests), `path_provider`, `url_launcher`, `dart:io` `Process`. Current version comes from the existing global `kAppVersion` (`app/lib/main.dart:36`). No new dependencies.

---

## File Structure

- **Create** `app/lib/models/app_release.dart` — `AppRelease`, `ReleaseAsset`, `UpdateStatus` enum. JSON parsing only; no logic.
- **Create** `app/lib/services/update_service.dart` — network + platform IO + pure helpers (`isNewerVersion`, `assetForPlatform`).
- **Create** `app/lib/providers/update_provider.dart` — state machine, debounce, orchestration.
- **Create** `app/lib/widgets/update_banner.dart` — dismissible top banner.
- **Modify** `app/lib/widgets/settings_screen.dart` — add an "Updates" `_Section`.
- **Modify** `app/lib/main.dart` — instantiate service+provider, add to `MultiProvider`, trigger post-frame check.
- **Modify** `app/lib/screens/main_screen.dart` — mount `UpdateBanner` between the top tab bar and the body.
- **Create** `app/test/services/update_service_test.dart` — unit tests for pure helpers + parsing + fetch (MockClient).
- **Create** `app/test/providers/update_provider_test.dart` — debounce + state-machine test with a fake service.

All commands run from `app/`.

---

### Task 1: AppRelease / ReleaseAsset / UpdateStatus models

**Files:**
- Create: `app/lib/models/app_release.dart`
- Test: `app/test/services/update_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/services/update_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_release.dart';

void main() {
  group('AppRelease.fromJson', () {
    final json = {
      'tag_name': 'v0.2.0',
      'name': 'YourSSH v0.2.0',
      'body': '## Changes\n- thing',
      'html_url': 'https://github.com/YoursshLabs/yourssh/releases/tag/v0.2.0',
      'published_at': '2026-06-01T10:00:00Z',
      'assets': [
        {
          'name': 'YourSSH-0.2.0-macOS-arm64.dmg',
          'browser_download_url': 'https://example.com/a.dmg',
          'size': 1234,
        },
      ],
    };

    test('strips leading v from version', () {
      expect(AppRelease.fromJson(json).version, '0.2.0');
    });

    test('parses tag, name, notes, url and publishedAt', () {
      final r = AppRelease.fromJson(json);
      expect(r.tagName, 'v0.2.0');
      expect(r.name, 'YourSSH v0.2.0');
      expect(r.notes, contains('thing'));
      expect(r.htmlUrl, contains('/tag/v0.2.0'));
      expect(r.publishedAt, DateTime.utc(2026, 6, 1, 10));
    });

    test('parses assets list', () {
      final r = AppRelease.fromJson(json);
      expect(r.assets, hasLength(1));
      expect(r.assets.first.name, 'YourSSH-0.2.0-macOS-arm64.dmg');
      expect(r.assets.first.downloadUrl, 'https://example.com/a.dmg');
      expect(r.assets.first.size, 1234);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/update_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/models/app_release.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/models/app_release.dart`:

```dart
/// Status of the in-app update check / download flow.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

/// A downloadable artifact attached to a GitHub release.
class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        name: json['name'] as String,
        downloadUrl: json['browser_download_url'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// A GitHub release as returned by the `releases/latest` endpoint.
class AppRelease {
  /// Tag with the leading `v` stripped, e.g. `0.2.0`.
  final String version;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  const AppRelease({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final published = json['published_at'] as String?;
    return AppRelease(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      tagName: tag,
      name: (json['name'] as String?) ?? tag,
      notes: (json['body'] as String?) ?? '',
      htmlUrl: (json['html_url'] as String?) ?? '',
      publishedAt: published == null ? null : DateTime.parse(published),
      assets: ((json['assets'] as List?) ?? const [])
          .map((e) => ReleaseAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/update_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/app_release.dart app/test/services/update_service_test.dart
git commit -m "feat(update): AppRelease/ReleaseAsset models + UpdateStatus"
```

---

### Task 2: UpdateService.isNewerVersion (pure semver)

**Files:**
- Create: `app/lib/services/update_service.dart`
- Test: `app/test/services/update_service_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `app/test/services/update_service_test.dart` (add the import at the top: `import 'package:yourssh/services/update_service.dart';`):

```dart
  group('isNewerVersion', () {
    final svc = UpdateService();
    test('equal versions are not newer', () {
      expect(svc.isNewerVersion('0.1.18', '0.1.18'), isFalse);
    });
    test('patch bump is newer', () {
      expect(svc.isNewerVersion('0.1.18', '0.1.19'), isTrue);
    });
    test('minor bump is newer', () {
      expect(svc.isNewerVersion('0.1.18', '0.2.0'), isTrue);
    });
    test('major bump is newer', () {
      expect(svc.isNewerVersion('0.9.9', '1.0.0'), isTrue);
    });
    test('older latest is not newer', () {
      expect(svc.isNewerVersion('0.2.0', '0.1.19'), isFalse);
    });
    test('leading v is tolerated on both sides', () {
      expect(svc.isNewerVersion('v0.1.18', 'v0.1.19'), isTrue);
    });
    test('pre-release / build suffix is ignored', () {
      expect(svc.isNewerVersion('0.1.18', '0.1.18-beta.1'), isFalse);
      expect(svc.isNewerVersion('0.1.18', '0.1.19+5'), isTrue);
    });
    test('unparseable input is treated as not newer (fail closed)', () {
      expect(svc.isNewerVersion('0.1.18', 'garbage'), isFalse);
      expect(svc.isNewerVersion('', '0.1.19'), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/update_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/services/update_service.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/services/update_service.dart`:

```dart
import 'package:yourssh/models/app_release.dart';

/// Network + platform glue for the in-app update flow.
/// Pure helpers (`isNewerVersion`, `assetForPlatform`) are unit-tested;
/// IO methods (`fetchLatestRelease`, `downloadAsset`, `launchInstaller`)
/// are added in later tasks.
class UpdateService {
  UpdateService();

  /// Returns true when [latest] is a strictly higher semantic version than
  /// [current]. Leading `v` and any `-pre`/`+build` suffix are ignored.
  /// Fails closed: unparseable [current] or [latest] never reports "newer"
  /// unless the parsed numbers genuinely differ.
  bool isNewerVersion(String current, String latest) {
    final a = _parse(current);
    final b = _parse(latest);
    for (var i = 0; i < 3; i++) {
      if (b[i] > a[i]) return true;
      if (b[i] < a[i]) return false;
    }
    return false;
  }

  /// Parses `major.minor.patch` into a 3-int list. Strips a leading `v` and
  /// drops anything from the first `-` or `+`. Missing/garbage segments -> 0.
  List<int> _parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    final cut = s.indexOf(RegExp(r'[-+]'));
    if (cut != -1) s = s.substring(0, cut);
    final parts = s.split('.');
    final out = <int>[0, 0, 0];
    for (var i = 0; i < 3 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/update_service_test.dart`
Expected: PASS (all `isNewerVersion` tests + Task 1 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/update_service.dart app/test/services/update_service_test.dart
git commit -m "feat(update): isNewerVersion semver comparison"
```

---

### Task 3: UpdateService.assetForPlatform (artifact selection)

**Files:**
- Modify: `app/lib/services/update_service.dart`
- Test: `app/test/services/update_service_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `app/test/services/update_service_test.dart`:

```dart
  group('assetForPlatform', () {
    final svc = UpdateService();
    AppRelease release() => AppRelease.fromJson({
          'tag_name': 'v0.2.0',
          'assets': [
            {'name': 'YourSSH-0.2.0-macOS-arm64.dmg', 'browser_download_url': 'u/mac', 'size': 1},
            {'name': 'YourSSH.Setup.0.2.0-Windows-x64.exe', 'browser_download_url': 'u/winsetup', 'size': 1},
            {'name': 'YourSSH-0.2.0-Windows-x64.exe', 'browser_download_url': 'u/winportable', 'size': 1},
            {'name': 'YourSSH.Setup.0.2.0-Windows-arm64.exe', 'browser_download_url': 'u/winarmsetup', 'size': 1},
            {'name': 'yourssh_0.2.0_amd64.deb', 'browser_download_url': 'u/deb64', 'size': 1},
            {'name': 'YourSSH-0.2.0-Linux-x86_64.tar.gz', 'browser_download_url': 'u/tgz64', 'size': 1},
            {'name': 'yourssh_0.2.0_arm64.deb', 'browser_download_url': 'u/debarm', 'size': 1},
          ],
        });

    test('macOS arm64 -> dmg', () {
      expect(svc.assetForPlatform(release(), os: 'macos', arch: 'arm64')!.name,
          'YourSSH-0.2.0-macOS-arm64.dmg');
    });
    test('macOS x64 -> null (no Intel artifact)', () {
      expect(svc.assetForPlatform(release(), os: 'macos', arch: 'x64'), isNull);
    });
    test('Windows x64 prefers Setup installer over portable', () {
      expect(svc.assetForPlatform(release(), os: 'windows', arch: 'x64')!.name,
          'YourSSH.Setup.0.2.0-Windows-x64.exe');
    });
    test('Windows arm64 -> arm64 Setup', () {
      expect(svc.assetForPlatform(release(), os: 'windows', arch: 'arm64')!.name,
          'YourSSH.Setup.0.2.0-Windows-arm64.exe');
    });
    test('Linux amd64 prefers .deb over tar.gz', () {
      expect(svc.assetForPlatform(release(), os: 'linux', arch: 'amd64')!.name,
          'yourssh_0.2.0_amd64.deb');
    });
    test('Linux arm64 -> arm64 .deb', () {
      expect(svc.assetForPlatform(release(), os: 'linux', arch: 'arm64')!.name,
          'yourssh_0.2.0_arm64.deb');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/update_service_test.dart`
Expected: FAIL — `The method 'assetForPlatform' isn't defined`.

- [ ] **Step 3: Write minimal implementation**

Add this method to the `UpdateService` class in `app/lib/services/update_service.dart` (before the closing brace):

```dart
  /// Picks the best matching asset for [os] (`macos`/`windows`/`linux`) and
  /// [arch] (`arm64`/`x64`/`amd64`). Returns null when no artifact matches
  /// (e.g. macOS x64 — only arm64 is shipped); callers then fall back to the
  /// browser. For each platform the candidate names are tried in preference
  /// order and the first asset whose name matches is returned.
  ReleaseAsset? assetForPlatform(
    AppRelease release, {
    required String os,
    required String arch,
  }) {
    bool present(String fragment, ReleaseAsset a) => a.name.contains(fragment);

    List<String> candidates() {
      switch (os) {
        case 'macos':
          return arch == 'arm64' ? const ['macOS-arm64.dmg'] : const [];
        case 'windows':
          return arch == 'arm64'
              ? const ['Setup.', 'arm64.exe'] // narrowed by the arch filter below
              : const ['Setup.', 'x64.exe'];
        case 'linux':
          return arch == 'arm64'
              ? const ['_arm64.deb', 'Linux-arm64.tar.gz']
              : const ['_amd64.deb', 'Linux-x86_64.tar.gz'];
        default:
          return const [];
      }
    }

    // Windows needs both an installer-vs-portable preference AND an arch match,
    // so handle it explicitly; other platforms match a single fragment.
    if (os == 'windows') {
      final archFrag = arch == 'arm64' ? 'arm64' : 'x64';
      // Preference: Setup (installer) first, then portable.
      for (final wantSetup in const [true, false]) {
        for (final a in release.assets) {
          final isSetup = a.name.contains('Setup.');
          if (a.name.contains(archFrag) &&
              a.name.endsWith('.exe') &&
              isSetup == wantSetup) {
            return a;
          }
        }
      }
      return null;
    }

    for (final frag in candidates()) {
      for (final a in release.assets) {
        if (present(frag, a)) return a;
      }
    }
    return null;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/update_service_test.dart`
Expected: PASS (all `assetForPlatform` tests + earlier groups).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/update_service.dart app/test/services/update_service_test.dart
git commit -m "feat(update): assetForPlatform artifact selection"
```

---

### Task 4: UpdateService IO — fetchLatestRelease, currentArch, downloadAsset, launchInstaller

**Files:**
- Modify: `app/lib/services/update_service.dart`
- Test: `app/test/services/update_service_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `app/test/services/update_service_test.dart` (add imports at the top: `import 'dart:convert';`, `import 'package:http/http.dart' as http;`, `import 'package:http/testing.dart';`):

```dart
  group('fetchLatestRelease', () {
    test('parses a 200 response', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(),
            'https://api.github.com/repos/YoursshLabs/yourssh/releases/latest');
        expect(req.headers['Accept'], 'application/vnd.github+json');
        return http.Response(
          jsonEncode({'tag_name': 'v0.2.0', 'assets': []}),
          200,
        );
      });
      final svc = UpdateService(client: client);
      final r = await svc.fetchLatestRelease();
      expect(r.version, '0.2.0');
    });

    test('throws UpdateException on non-200 (e.g. rate limit)', () async {
      final client = MockClient((req) async => http.Response('rate limited', 403));
      final svc = UpdateService(client: client);
      expect(svc.fetchLatestRelease(), throwsA(isA<UpdateException>()));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/update_service_test.dart`
Expected: FAIL — `UpdateService` has no `client` parameter / `UpdateException` undefined.

- [ ] **Step 3: Write minimal implementation**

Edit `app/lib/services/update_service.dart`. Replace the imports + constructor at the top and append the IO methods. New full top of file:

```dart
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:yourssh/models/app_release.dart';

/// Thrown when the update flow cannot complete (network, parse, no asset, IO).
class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => 'UpdateException: $message';
}

/// Network + platform glue for the in-app update flow.
class UpdateService {
  UpdateService({http.Client? client, this.repo = 'YoursshLabs/yourssh'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String repo;
```

Keep the existing `isNewerVersion`, `_parse`, and `assetForPlatform` methods unchanged. Before the final closing brace of the class, add:

```dart
  /// Fetches the latest *stable* release (GitHub's `releases/latest` excludes
  /// drafts and pre-releases). Throws [UpdateException] on network/HTTP/parse
  /// failure.
  Future<AppRelease> fetchLatestRelease() async {
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    try {
      final res = await _client.get(uri, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      });
      if (res.statusCode != 200) {
        throw UpdateException('GitHub responded ${res.statusCode}');
      }
      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) {
        throw UpdateException('Unexpected response shape');
      }
      return AppRelease.fromJson(body);
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException('Could not check for updates: $e');
    }
  }

  /// CPU architecture token used by [assetForPlatform].
  /// macOS only ships arm64; Windows reads PROCESSOR_ARCHITECTURE; Linux
  /// shells out to `uname -m`.
  String currentArch() {
    if (Platform.isMacOS) return 'arm64';
    if (Platform.isWindows) {
      final p = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
      return p.contains('ARM64') ? 'arm64' : 'x64';
    }
    if (Platform.isLinux) {
      try {
        final m = Process.runSync('uname', const ['-m']).stdout.toString().trim();
        return (m == 'aarch64' || m == 'arm64') ? 'arm64' : 'amd64';
      } catch (_) {
        return 'amd64';
      }
    }
    return 'x64';
  }

  /// OS token used by [assetForPlatform].
  String currentOs() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  /// Streams [asset] to the Downloads directory, reporting progress 0.0..1.0.
  /// Removes a partial file and throws [UpdateException] on failure.
  Future<File> downloadAsset(
    ReleaseAsset asset, {
    required void Function(double) onProgress,
  }) async {
    final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final file = File('${dir.path}/${asset.name}');
    try {
      final req = http.Request('GET', Uri.parse(asset.downloadUrl));
      final res = await _client.send(req);
      if (res.statusCode != 200) {
        throw UpdateException('Download failed (${res.statusCode})');
      }
      final total = res.contentLength ?? asset.size;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      onProgress(1.0);
      return file;
    } catch (e) {
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (e is UpdateException) rethrow;
      throw UpdateException('Download failed: $e');
    }
  }

  /// Hands [file] off to the OS installer. macOS strips quarantine then opens
  /// the DMG; Windows runs the installer exe; Linux opens with the desktop
  /// handler. Throws [UpdateException] on failure.
  Future<void> launchInstaller(File file) async {
    final path = file.path;
    try {
      if (Platform.isMacOS) {
        // Best-effort: our own download usually carries no quarantine xattr,
        // but strip it anyway so Gatekeeper does not block the new build.
        await Process.run('xattr', ['-dr', 'com.apple.quarantine', path]);
        final r = await Process.run('open', [path]);
        if (r.exitCode != 0) throw UpdateException('open failed: ${r.stderr}');
      } else if (Platform.isWindows) {
        await Process.start(path, const [], mode: ProcessStartMode.detached);
      } else {
        final r = await Process.run('xdg-open', [path]);
        if (r.exitCode != 0) throw UpdateException('xdg-open failed: ${r.stderr}');
      }
    } catch (e) {
      if (e is UpdateException) rethrow;
      throw UpdateException('Could not launch installer: $e');
    }
  }
```

Also add `import 'dart:convert';` to the top imports (used by `fetchLatestRelease`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/update_service_test.dart`
Expected: PASS (fetch tests + all earlier groups). `downloadAsset`/`launchInstaller`/`currentArch` are platform-IO and verified manually later.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/update_service.dart app/test/services/update_service_test.dart
git commit -m "feat(update): fetchLatestRelease, download + launchInstaller, platform tokens"
```

---

### Task 5: UpdateProvider (state machine + 24h debounce)

**Files:**
- Create: `app/lib/providers/update_provider.dart`
- Test: `app/test/providers/update_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/providers/update_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/update_service.dart';

/// Counts fetches and returns a scripted release.
class _FakeService extends UpdateService {
  _FakeService(this._release);
  final AppRelease _release;
  int fetchCount = 0;
  @override
  Future<AppRelease> fetchLatestRelease() async {
    fetchCount++;
    return _release;
  }
}

AppRelease _rel(String tag) =>
    AppRelease.fromJson({'tag_name': tag, 'assets': []});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual check finds a newer version -> available', () async {
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.status, UpdateStatus.available);
    expect(p.latestRelease!.version, '0.2.0');
    expect(svc.fetchCount, 1);
  });

  test('same version -> upToDate', () async {
    final svc = _FakeService(_rel('v0.1.18'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.status, UpdateStatus.upToDate);
  });

  test('auto check is skipped within 24h of the last check', () async {
    final now = DateTime.utc(2026, 6, 3, 12);
    SharedPreferences.setMockInitialValues({
      'last_update_check': now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    });
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18', now: () => now);
    await p.checkForUpdates(); // auto
    expect(svc.fetchCount, 0);
    expect(p.status, UpdateStatus.idle);
  });

  test('auto check runs when >24h since last check', () async {
    final now = DateTime.utc(2026, 6, 3, 12);
    SharedPreferences.setMockInitialValues({
      'last_update_check': now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
    });
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18', now: () => now);
    await p.checkForUpdates(); // auto
    expect(svc.fetchCount, 1);
    expect(p.status, UpdateStatus.available);
  });

  test('dismiss hides the banner for that version only', () async {
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.showBanner, isTrue);
    p.dismiss();
    expect(p.showBanner, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/update_provider_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/providers/update_provider.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/providers/update_provider.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/services/update_service.dart';

/// Drives the in-app update flow: debounced launch check + manual check,
/// download, and install hand-off. Surfaces state to the banner and Settings.
class UpdateProvider extends ChangeNotifier {
  UpdateProvider(
    this._service, {
    required this.currentVersion,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _lastCheckKey = 'last_update_check';
  static const _dismissedKey = 'update_dismissed_version';
  static const _minInterval = Duration(hours: 24);

  final UpdateService _service;
  final String currentVersion;
  final DateTime Function() _now;

  UpdateStatus status = UpdateStatus.idle;
  AppRelease? latestRelease;
  double downloadProgress = 0;
  String? errorMessage;
  String? _dismissedVersion;
  File? _downloadedFile;

  bool get showBanner =>
      status == UpdateStatus.available &&
      latestRelease != null &&
      latestRelease!.version != _dismissedVersion;

  /// Checks GitHub for a newer stable release. Auto checks (`manual == false`)
  /// are skipped if the last check was under 24h ago; manual checks always run.
  Future<void> checkForUpdates({bool manual = false}) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedVersion ??= prefs.getString(_dismissedKey);

    if (!manual) {
      final last = prefs.getInt(_lastCheckKey);
      if (last != null) {
        final elapsed = _now().difference(
          DateTime.fromMillisecondsSinceEpoch(last),
        );
        if (elapsed < _minInterval) return;
      }
    }

    status = UpdateStatus.checking;
    errorMessage = null;
    notifyListeners();

    try {
      final release = await _service.fetchLatestRelease();
      await prefs.setInt(_lastCheckKey, _now().millisecondsSinceEpoch);
      latestRelease = release;
      status = _service.isNewerVersion(currentVersion, release.version)
          ? UpdateStatus.available
          : UpdateStatus.upToDate;
    } on UpdateException catch (e) {
      status = UpdateStatus.error;
      errorMessage = e.message;
    } catch (e) {
      status = UpdateStatus.error;
      errorMessage = 'Could not check for updates: $e';
    }
    notifyListeners();
  }

  /// Downloads the matching artifact and hands it to the OS installer.
  /// Falls back to opening the Releases page when no asset matches the
  /// current OS/arch or when launching the installer fails.
  Future<void> downloadAndInstall() async {
    final release = latestRelease;
    if (release == null) return;

    final asset = _service.assetForPlatform(
      release,
      os: _service.currentOs(),
      arch: _service.currentArch(),
    );
    if (asset == null) {
      await _openReleasePage(release);
      return;
    }

    status = UpdateStatus.downloading;
    downloadProgress = 0;
    errorMessage = null;
    notifyListeners();

    try {
      final file = await _service.downloadAsset(asset, onProgress: (p) {
        downloadProgress = p;
        notifyListeners();
      });
      _downloadedFile = file;
      status = UpdateStatus.readyToInstall;
      notifyListeners();
      await _service.launchInstaller(file);
    } on UpdateException catch (e) {
      status = UpdateStatus.error;
      errorMessage = e.message;
      notifyListeners();
      await _openReleasePage(release);
    }
  }

  Future<void> _openReleasePage(AppRelease release) async {
    final uri = Uri.tryParse(release.htmlUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Hides the banner for the current latest version (persisted).
  void dismiss() {
    final v = latestRelease?.version;
    if (v == null) return;
    _dismissedVersion = v;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_dismissedKey, v));
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/update_provider_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/update_provider.dart app/test/providers/update_provider_test.dart
git commit -m "feat(update): UpdateProvider state machine + 24h debounce"
```

---

### Task 6: UpdateBanner widget

**Files:**
- Create: `app/lib/widgets/update_banner.dart`
- Test: `app/test/widgets/update_banner_test.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/widgets/update_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/update_service.dart';
import 'package:yourssh/widgets/update_banner.dart';

class _StubService extends UpdateService {
  _StubService(this._release);
  final AppRelease _release;
  @override
  Future<AppRelease> fetchLatestRelease() async => _release;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, UpdateProvider p) {
    return tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: p,
        child: MaterialApp(
          home: Scaffold(body: UpdateBanner(onShowDetails: () {})),
        ),
      ),
    );
  }

  testWidgets('hidden when up to date', (tester) async {
    final p = UpdateProvider(
      _StubService(AppRelease.fromJson({'tag_name': 'v0.1.18', 'assets': []})),
      currentVersion: '0.1.18',
    );
    await p.checkForUpdates(manual: true);
    await pump(tester, p);
    expect(find.byType(UpdateBanner), findsOneWidget);
    expect(find.textContaining('available'), findsNothing);
  });

  testWidgets('shows version when an update is available', (tester) async {
    final p = UpdateProvider(
      _StubService(AppRelease.fromJson({'tag_name': 'v0.2.0', 'assets': []})),
      currentVersion: '0.1.18',
    );
    await p.checkForUpdates(manual: true);
    await pump(tester, p);
    expect(find.textContaining('0.2.0'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/update_banner_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/widgets/update_banner.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `app/lib/widgets/update_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/theme/app_theme.dart';

/// Dismissible banner shown at the top of the app when a newer release is
/// available. [onShowDetails] navigates to the Settings update section.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.onShowDetails});

  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();
    if (!provider.showBanner) return const SizedBox.shrink();
    final version = provider.latestRelease!.version;

    return Material(
      color: AppColors.accent.withValues(alpha: 0.12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt, size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'New version v$version available',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onShowDetails,
              child: const Text('Details'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => context.read<UpdateProvider>().downloadAndInstall(),
              child: const Text('Update'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              onPressed: () => context.read<UpdateProvider>().dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/update_banner_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/update_banner.dart app/test/widgets/update_banner_test.dart
git commit -m "feat(update): dismissible UpdateBanner widget"
```

---

### Task 7: Settings "Updates" section

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

> The settings screen builds a `ListView` of `_Section(title:, children: [...])`
> blocks separated by `const SizedBox(height: 24)` (see `app/lib/widgets/settings_screen.dart:80`).
> Add a new section near the end of that list (before the closing `]` of the
> ListView `children`). `_Section` and `_Row` already exist in this file.

- [ ] **Step 1: Add the import**

At the top of `app/lib/widgets/settings_screen.dart`, add (next to the other provider imports):

```dart
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/models/app_release.dart';
```

- [ ] **Step 2: Read the current version into build**

In `build`, just after `final sync = context.watch<SyncProvider>();`, add:

```dart
    final update = context.watch<UpdateProvider>();
```

- [ ] **Step 3: Add the Updates section to the ListView**

Immediately before the final closing `]` of the ListView `children:` list (after the last existing section), add:

```dart
                const SizedBox(height: 24),
                _Section(title: 'Updates', children: [
                  _Row(
                    label: 'Current version',
                    trailing: Text(
                      'v${update.currentVersion}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  _Row(
                    label: 'Status',
                    subtitle: _updateStatusText(update),
                    trailing: update.status == UpdateStatus.downloading
                        ? SizedBox(
                            width: 120,
                            child: LinearProgressIndicator(value: update.downloadProgress),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (update.status == UpdateStatus.available)
                                FilledButton(
                                  onPressed: () =>
                                      context.read<UpdateProvider>().downloadAndInstall(),
                                  child: const Text('Download & install'),
                                ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: update.status == UpdateStatus.checking
                                    ? null
                                    : () => context
                                        .read<UpdateProvider>()
                                        .checkForUpdates(manual: true),
                                child: const Text('Check for updates'),
                              ),
                            ],
                          ),
                  ),
                  if (update.status == UpdateStatus.available &&
                      update.latestRelease != null &&
                      update.latestRelease!.notes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        update.latestRelease!.notes,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                ]),
```

- [ ] **Step 4: Add the status-text helper**

Inside the `State` class (near `_buildFontDropdown`), add:

```dart
  String _updateStatusText(UpdateProvider u) {
    switch (u.status) {
      case UpdateStatus.checking:
        return 'Checking…';
      case UpdateStatus.upToDate:
        return 'You are on the latest version';
      case UpdateStatus.available:
        return 'New version v${u.latestRelease!.version} available';
      case UpdateStatus.downloading:
        return 'Downloading…';
      case UpdateStatus.readyToInstall:
        return 'Opening installer…';
      case UpdateStatus.error:
        return u.errorMessage ?? 'Could not check for updates';
      case UpdateStatus.idle:
        return 'Tap "Check for updates" to look for a new version';
    }
  }
```

- [ ] **Step 5: Verify it compiles**

Run: `flutter analyze lib/widgets/settings_screen.dart`
Expected: No errors (warnings about existing code are fine).

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat(update): Updates section in Settings"
```

---

### Task 8: Wire into main.dart + mount banner in MainScreen

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add imports in main.dart**

Add near the other provider/service imports in `app/lib/main.dart`:

```dart
import 'package:yourssh/services/update_service.dart';
import 'package:yourssh/providers/update_provider.dart';
```

- [ ] **Step 2: Add fields + instantiate**

Where the other providers are created (around `app/lib/main.dart:130-216`), add a field and instantiate after `kAppVersion` is known:

```dart
  late final UpdateService _updateService;
  late final UpdateProvider _updateProvider;
```

In the same init block (after the other providers, e.g. after `_syncProvider = ...`):

```dart
    _updateService = UpdateService();
    _updateProvider = UpdateProvider(_updateService, currentVersion: kAppVersion);
```

- [ ] **Step 3: Register in MultiProvider**

In the `MultiProvider` `providers: [...]` list (around `app/lib/main.dart:296`), add alongside the other `.value` providers:

```dart
        ChangeNotifierProvider.value(value: _updateProvider),
```

- [ ] **Step 4: Trigger the debounced launch check**

In the same `State`'s `initState` (or right after providers are wired), add a post-frame callback so the check runs once the tree is mounted:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateProvider.checkForUpdates();
    });
```

(If an `addPostFrameCallback` already exists in `initState`, add the
`_updateProvider.checkForUpdates();` line inside it instead of adding a second.)

- [ ] **Step 5: Mount the banner in MainScreen**

In `app/lib/screens/main_screen.dart`, add the import:

```dart
import 'package:yourssh/widgets/update_banner.dart';
```

In `build`, the body is a `Column` whose first child is `_TopTabBar(...)` and second is `Expanded(child: Row(...))` (see `app/lib/screens/main_screen.dart:501`). Insert the banner between them — directly after the `_TopTabBar(...)` widget's closing `),` and before `Expanded(`:

```dart
          UpdateBanner(
            onShowDetails: () => setState(() {
              _activePluginId = null;
              _activeScriptPanel = null;
              _nav = NavSection.settings;
              _viewingTerminal = false;
              _showAiChat = false;
            }),
          ),
```

- [ ] **Step 6: Verify it compiles and tests pass**

Run: `flutter analyze`
Expected: No new errors.

Run: `flutter test`
Expected: PASS (all suites, including the three new update test files).

- [ ] **Step 7: Commit**

```bash
git add app/lib/main.dart app/lib/screens/main_screen.dart
git commit -m "feat(update): wire UpdateProvider + mount banner in MainScreen"
```

---

### Task 9: Manual verification (platform IO not covered by unit tests)

**Files:** none (manual)

- [ ] **Step 1: Temporarily force an "available" state**

In `app/lib/main.dart`, temporarily construct the provider with an older
`currentVersion` to force a hit (revert before committing):

```dart
    _updateProvider = UpdateProvider(_updateService, currentVersion: '0.0.1');
```

- [ ] **Step 2: Run the app**

Run: `flutter run -d macos`
Expected: After launch the banner appears ("New version vX.Y.Z available").
Open Settings → Updates: current version, status, release notes, and buttons render.

- [ ] **Step 3: Exercise the flow**

Click **Update** (or **Download & install** in Settings). Expected: progress
advances, then the DMG mounts (macOS) / installer launches (Windows) / file
opens (Linux). On an Intel Mac (no arm64 match) expect the browser to open the
Releases page instead.

- [ ] **Step 4: Revert the forced version**

Restore `currentVersion: kAppVersion` in `app/lib/main.dart`. Re-run
`flutter analyze` and `flutter test`.

- [ ] **Step 5: Commit (only if any code changed during verification)**

```bash
git add -A && git commit -m "chore(update): revert forced version after manual verification"
```

---

## Self-Review Notes

- **Spec coverage:** check trigger (Task 5 debounce + Task 8 post-frame + Settings manual button Task 7) ✓; banner + Settings surface (Tasks 6, 7, 8) ✓; stable-only via `releases/latest` (Task 4) ✓; asset table incl. Intel-Mac fallback (Tasks 3, 5) ✓; error handling no-silent-fail (Tasks 4, 5) ✓; tests for `isNewerVersion`/`assetForPlatform`/`fromJson` (Tasks 1-4) ✓.
- **Types consistent across tasks:** `UpdateStatus`, `AppRelease.version`, `ReleaseAsset.downloadUrl`, `UpdateService.{isNewerVersion, assetForPlatform, fetchLatestRelease, currentOs, currentArch, downloadAsset, launchInstaller}`, `UpdateProvider.{checkForUpdates, downloadAndInstall, dismiss, showBanner, status, latestRelease, currentVersion, downloadProgress, errorMessage}` — all defined before use.
- **No placeholders:** every code step contains full code.

## Docs / release checklist (before PR to master)

Per repo convention, before merging to `master`: update `CHANGELOG.md` ([Unreleased] → versioned), bump `app/pubspec.yaml` version, update README "Download"/feature list to mention in-app updates, and the wiki release note. (Not part of the per-task TDD loop.)
