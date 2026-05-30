# OS Detection & Host Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a successful SSH connection, detect the remote OS and persist it so the host list renders a matching SVG icon (Linux/macOS/Windows) instead of the generic `Icons.dns`.

**Architecture:** Add `detectedOs: String?` to `Host`; `SshService.detectOs(host)` runs `uname -s` and parses the output; `SessionProvider` triggers detection once (only when `host.detectedOs == null`) and calls `onOsDetected` callback; `HostProvider.updateDetectedOs` saves to `SharedPreferences`; the UI uses `flutter_svg` to render from `assets/os/<os>.svg`.

**Tech Stack:** Flutter/Dart, shared_preferences (existing), flutter_svg (new), SVG image assets.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/models/host.dart` | Modify | Add `detectedOs` field, serialize/deserialize |
| `app/lib/services/ssh_service.dart` | Modify | Add `detectOs(Host)` method |
| `app/lib/providers/host_provider.dart` | Modify | Add `updateDetectedOs(hostId, os)` method |
| `app/lib/providers/session_provider.dart` | Modify | Add `onOsDetected` callback, call after connect |
| `app/lib/main.dart` | Modify | Wire `onOsDetected` → `hostProvider.updateDetectedOs` |
| `app/lib/widgets/hosts_dashboard.dart` | Modify | Replace `Icons.dns` with `_osIcon(host)` widget |
| `app/pubspec.yaml` | Modify | Add flutter_svg dep + `assets/os/` path |
| `app/assets/os/linux.svg` | Create | Linux OS icon (terminal/prompt) |
| `app/assets/os/macos.svg` | Create | macOS OS icon (Apple logo) |
| `app/assets/os/windows.svg` | Create | Windows OS icon (4-pane flag) |
| `app/test/models/host_detected_os_test.dart` | Create | Test detectedOs serialization |
| `app/test/services/ssh_service_detect_os_test.dart` | Create | Test detectOs output parsing |

---

## Task 1: Add `detectedOs` to Host model

**Files:**
- Modify: `app/lib/models/host.dart`
- Create: `app/test/models/host_detected_os_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/models/host_detected_os_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host.detectedOs', () {
    test('toJson includes detectedOs when set', () {
      final host = Host(
        id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u',
        detectedOs: 'linux',
      );
      expect(host.toJson()['detectedOs'], 'linux');
    });

    test('toJson includes null detectedOs when unset', () {
      final host = Host(id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u');
      expect(host.toJson()['detectedOs'], isNull);
    });

    test('fromJson restores detectedOs', () {
      final json = {
        'id': 'h1', 'label': 'box', 'host': '1.2.3.4', 'port': 22,
        'username': 'u', 'authType': 'password', 'group': '',
        'tags': <String>[], 'createdAt': '2026-01-01T00:00:00.000Z',
        'detectedOs': 'macos',
      };
      expect(Host.fromJson(json).detectedOs, 'macos');
    });

    test('fromJson defaults detectedOs to null when key absent', () {
      final json = {
        'id': 'h1', 'label': 'box', 'host': '1.2.3.4', 'port': 22,
        'username': 'u', 'authType': 'password', 'group': '',
        'tags': <String>[], 'createdAt': '2026-01-01T00:00:00.000Z',
      };
      expect(Host.fromJson(json).detectedOs, isNull);
    });

    test('copyWith preserves detectedOs when not overridden', () {
      final host = Host(
        id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u',
        detectedOs: 'windows',
      );
      expect(host.copyWith(label: 'new').detectedOs, 'windows');
    });

    test('copyWith can update detectedOs', () {
      final host = Host(
        id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u',
        detectedOs: 'linux',
      );
      expect(host.copyWith(detectedOs: 'macos').detectedOs, 'macos');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/models/host_detected_os_test.dart
```

Expected: compile error — `detectedOs` not yet defined.

- [ ] **Step 3: Implement `detectedOs` in Host model**

In `app/lib/models/host.dart`, apply these changes:

```dart
// Add field after 'tags':
String? detectedOs;

// Update constructor — add after tags parameter:
this.detectedOs,

// Update toJson — add after 'tags':
'detectedOs': detectedOs,

// Update fromJson — add after tags line:
detectedOs: json['detectedOs'] as String?,

// Update copyWith — add parameter after group:
String? detectedOs,

// Update copyWith return — add field (use ?? this.detectedOs so null can't override):
detectedOs: detectedOs ?? this.detectedOs,
```

Full file after changes:

```dart
import 'package:uuid/uuid.dart';

enum AuthType { password, privateKey, certificate, agent }

class Host {
  final String id;
  String label;
  String host;
  int port;
  String username;
  AuthType authType;
  String? keyId;
  String group;
  List<String> tags;
  DateTime createdAt;
  String? detectedOs;

  Host({
    String? id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = AuthType.password,
    this.keyId,
    this.group = '',
    this.tags = const [],
    DateTime? createdAt,
    this.detectedOs,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType.name,
        'keyId': keyId,
        'group': group,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'detectedOs': detectedOs,
      };

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'],
        label: json['label'],
        host: json['host'],
        port: json['port'] ?? 22,
        username: json['username'],
        authType: AuthType.values.byName(json['authType'] ?? 'password'),
        keyId: json['keyId'],
        group: json['group'] ?? '',
        tags: List<String>.from(json['tags'] ?? []),
        createdAt: DateTime.parse(json['createdAt']),
        detectedOs: json['detectedOs'] as String?,
      );

  Host copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    AuthType? authType,
    String? keyId,
    String? group,
    String? detectedOs,
  }) =>
      Host(
        id: id,
        label: label ?? this.label,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        authType: authType ?? this.authType,
        keyId: keyId ?? this.keyId,
        group: group ?? this.group,
        tags: tags,
        createdAt: createdAt,
        detectedOs: detectedOs ?? this.detectedOs,
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/models/host_detected_os_test.dart
```

Expected: 6 tests pass.

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
cd app && flutter test
```

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_detected_os_test.dart
git commit -m "feat: add detectedOs field to Host model"
```

---

## Task 2: Add `detectOs` to SshService

**Files:**
- Modify: `app/lib/services/ssh_service.dart`
- Create: `app/test/services/ssh_service_detect_os_test.dart`

- [ ] **Step 1: Write the failing tests**

The `detectOs` logic is pure string parsing, so extract a testable static helper `SshService.parseOsFromUname(String output)` alongside the async method.

Create `app/test/services/ssh_service_detect_os_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/ssh_service.dart';

void main() {
  group('SshService.parseOsFromUname', () {
    test('Linux output returns linux', () {
      expect(SshService.parseOsFromUname('Linux'), 'linux');
    });

    test('Darwin output returns macos', () {
      expect(SshService.parseOsFromUname('Darwin'), 'macos');
    });

    test('Windows_NT output returns windows', () {
      expect(SshService.parseOsFromUname('Windows_NT'), 'windows');
    });

    test('MINGW output returns windows', () {
      expect(SshService.parseOsFromUname('MINGW64_NT-10.0'), 'windows');
    });

    test('CYGWIN output returns windows', () {
      expect(SshService.parseOsFromUname('CYGWIN_NT-10.0'), 'windows');
    });

    test('empty output returns null', () {
      expect(SshService.parseOsFromUname(''), isNull);
    });

    test('unknown output returns null', () {
      expect(SshService.parseOsFromUname('FreeBSD'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/services/ssh_service_detect_os_test.dart
```

Expected: compile error — `parseOsFromUname` not defined.

- [ ] **Step 3: Implement `parseOsFromUname` and `detectOs` in SshService**

Add after the `isConnected` method (end of `app/lib/services/ssh_service.dart`):

```dart
  // ── OS Detection ────────────────────────────────────────

  static String? parseOsFromUname(String output) {
    final s = output.trim();
    if (s.contains('Linux')) return 'linux';
    if (s.contains('Darwin')) return 'macos';
    if (s.contains('Windows') || s.contains('MINGW') || s.contains('CYGWIN')) return 'windows';
    return null;
  }

  Future<String?> detectOs(Host host) async {
    try {
      final result = await exec(host, 'uname -s 2>/dev/null || ver');
      return parseOsFromUname(result.stdout);
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/services/ssh_service_detect_os_test.dart
```

Expected: 7 tests pass.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_detect_os_test.dart
git commit -m "feat: add detectOs and parseOsFromUname to SshService"
```

---

## Task 3: Add `updateDetectedOs` to HostProvider

**Files:**
- Modify: `app/lib/providers/host_provider.dart`

- [ ] **Step 1: Write the failing test**

Add a new test group to an existing or new file. Create `app/test/providers/host_provider_os_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostProvider.updateDetectedOs', () {
    late HostProvider provider;
    late Host host;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = HostProvider(StorageService());
      host = Host(id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u');
      await provider.addHost(host);
    });

    test('sets detectedOs on matching host', () async {
      await provider.updateDetectedOs('h1', 'linux');
      expect(provider.allHosts.first.detectedOs, 'linux');
    });

    test('persists detectedOs across provider reload', () async {
      await provider.updateDetectedOs('h1', 'macos');
      final provider2 = HostProvider(StorageService());
      await Future.delayed(Duration.zero);
      expect(provider2.allHosts.first.detectedOs, 'macos');
    });

    test('does not call onMutation', () async {
      var mutationCalled = false;
      provider.onMutation = () async => mutationCalled = true;
      await provider.updateDetectedOs('h1', 'linux');
      expect(mutationCalled, isFalse);
    });

    test('no-ops for unknown hostId', () async {
      await provider.updateDetectedOs('unknown', 'linux');
      expect(provider.allHosts.first.detectedOs, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/providers/host_provider_os_test.dart
```

Expected: compile error — `updateDetectedOs` not defined.

- [ ] **Step 3: Implement `updateDetectedOs` in HostProvider**

Add after `deleteHost` method in `app/lib/providers/host_provider.dart`:

```dart
  Future<void> updateDetectedOs(String hostId, String os) async {
    final idx = _hosts.indexWhere((h) => h.id == hostId);
    if (idx == -1) return;
    _hosts[idx] = _hosts[idx].copyWith(detectedOs: os);
    await _storage.saveHosts(_hosts);
    notifyListeners();
    // intentionally does NOT call onMutation — local metadata only
  }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/providers/host_provider_os_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/providers/host_provider.dart app/test/providers/host_provider_os_test.dart
git commit -m "feat: add updateDetectedOs to HostProvider"
```

---

## Task 4: Wire OS detection in SessionProvider and main.dart

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Add `onOsDetected` callback to SessionProvider**

In `app/lib/providers/session_provider.dart`, add the callback field after `hostKeyVerifier`:

```dart
  Future<void> Function(String hostId, String os)? onOsDetected;
```

Then in `_doConnect`, after `session.status = SessionStatus.connected;` and before `session.errorMessage = null;`, add the fire-and-forget detection call:

```dart
      session.status = SessionStatus.connected;
      // Fire-and-forget: only detect if OS not yet known
      if (host.detectedOs == null) {
        _ssh.detectOs(host).then((os) {
          if (os != null) onOsDetected?.call(host.id, os);
        });
      }
      session.errorMessage = null;
```

- [ ] **Step 2: Wire callback in main.dart**

In `app/lib/main.dart`, after the existing `_sessionProvider.hostKeyVerifier = ...` line (around line 77), add:

```dart
    _sessionProvider.onOsDetected = (hostId, os) =>
        _hostProvider.updateDetectedOs(hostId, os);
```

- [ ] **Step 3: Analyze to check for errors**

```bash
cd app && flutter analyze lib/providers/session_provider.dart lib/main.dart
```

Expected: no issues.

- [ ] **Step 4: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/lib/main.dart
git commit -m "feat: trigger OS detection after SSH connect, wire to HostProvider"
```

---

## Task 5: Add flutter_svg and SVG icon assets

**Files:**
- Modify: `app/pubspec.yaml`
- Create: `app/assets/os/linux.svg`
- Create: `app/assets/os/macos.svg`
- Create: `app/assets/os/windows.svg`

- [ ] **Step 1: Add flutter_svg to pubspec.yaml**

In `app/pubspec.yaml`, add `flutter_svg: ^2.0.10` under dependencies (after `provider`):

```yaml
  # SVG rendering for OS icons
  flutter_svg: ^2.0.10
```

Also add `assets/os/` directory registration under `flutter: assets:`:

```yaml
  assets:
    - assets/monaco_editor.html
    - assets/app_icon.png
    - assets/os/
```

- [ ] **Step 2: Run flutter pub get**

```bash
cd app && flutter pub get
```

Expected: resolves flutter_svg without conflicts.

- [ ] **Step 3: Create linux.svg**

Create `app/assets/os/linux.svg` (terminal/monitor icon, clearly Linux-associated):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="white" d="M20 3H4a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h3l-1 3h8l-1-3h3a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 13H4V5h16v11zM6 7.5l1.5 1.5L6 10.5V13h2v-1.5l2-2L8 7.5H6zm5 3.5v2h6v-2h-6z"/>
</svg>
```

- [ ] **Step 4: Create macos.svg**

Create `app/assets/os/macos.svg` (Apple logo):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="white" d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
</svg>
```

- [ ] **Step 5: Create windows.svg**

Create `app/assets/os/windows.svg` (Windows 4-pane logo):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="white" d="M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-13.051-1.8"/>
</svg>
```

- [ ] **Step 6: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/assets/os/
git commit -m "feat: add flutter_svg and OS icon SVG assets"
```

---

## Task 6: Update hosts_dashboard.dart to show OS icons

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart`

- [ ] **Step 1: Add flutter_svg import**

At the top of `app/lib/widgets/hosts_dashboard.dart`, add after the last import:

```dart
import 'package:flutter_svg/flutter_svg.dart';
```

- [ ] **Step 2: Replace hardcoded `Icons.dns` with `_osIcon` helper**

Locate the host icon container (around line 541-551):

```dart
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.dns, color: Colors.white, size: 18),
              ),
```

Replace with:

```dart
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _osIcon(widget.host),
              ),
```

- [ ] **Step 3: Add `_osIcon` helper method to `_HostCardState`**

Add this method inside `_HostCardState` (before or after `_buildTopBar`, near other small helpers):

```dart
  Widget _osIcon(Host host) {
    if (host.detectedOs != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SvgPicture.asset(
          'assets/os/${host.detectedOs}.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return const Icon(Icons.dns, color: Colors.white, size: 18);
  }
```

- [ ] **Step 4: Analyze for errors**

```bash
cd app && flutter analyze lib/widgets/hosts_dashboard.dart
```

Expected: no issues.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "feat: show OS-specific SVG icon on host cards after detection"
```

---

## Done — Verification Checklist

- [ ] Connect to a Linux host → wait 1–2 s → host card updates to terminal/Linux icon
- [ ] Disconnect and reconnect → icon already shows (detectedOs cached, no re-detection)
- [ ] Restart the app → icon persists (saved to SharedPreferences)
- [ ] Hosts with no successful connection still show `Icons.dns`
- [ ] `flutter analyze` passes with zero issues
- [ ] `flutter test` passes with zero failures
