# Quick Wins Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship four small polish features: middle-click closes unpinned session tabs, duplicate port-forward rule via right-click menu, distro-level host OS icons (host list + session tabs), and tests locking the existing empty-password SSH behavior.

**Architecture:** A new pure helper `os_detection.dart` owns os-release parsing and the OS-icon asset mapping (shared by dashboard + tab bar). `_SessionTab` is extracted out of the 1800-line `main_screen.dart` into its own widget file so the tab behaviors (middle-click, OS icon) become widget-testable. The port-forward tile gains a context menu following the existing tab-context-menu pattern. No model changes anywhere.

**Tech Stack:** Flutter (provider, flutter_svg, flutter_test), dartssh2 fork (untouched).

**Spec:** `docs/superpowers/specs/2026-06-05-quick-wins-bundle-design.md`

**Conventions for every task:** run commands from the repo root. `flutter` commands run in `app/` (`cd app && …`). After each task's tests pass, also run `cd app && flutter analyze` and fix any new warnings before committing.

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/services/os_detection.dart` | Create | Pure: parse `/etc/os-release` ID, normalize distro ids, OS-icon asset mapping |
| `app/test/services/os_detection_test.dart` | Create | Unit tests for the above + asset-presence guard |
| `app/assets/os/*.svg` (11 new) | Create | Simplified monochrome distro glyphs (style of existing linux/macos/windows) |
| `app/lib/widgets/hosts_dashboard.dart` | Modify | `_osIcon` uses `osIconAsset()`; drop private `_osAssets` |
| `app/lib/services/ssh_service.dart` | Modify | `detectOs` probes `/etc/os-release` when uname says Linux |
| `app/lib/providers/session_provider.dart` | Modify | Re-detect when `detectedOs` is null **or** generic `'linux'` |
| `app/lib/widgets/session_tab.dart` | Create | Extracted public `SessionTab` (from `_SessionTab`) + middle-click close + OS icon |
| `app/lib/screens/main_screen.dart` | Modify | Remove `_SessionTab`/`_healthTooltip`/`_fmtDuration`, use `SessionTab` |
| `app/test/widgets/session_tab_test.dart` | Create | Middle-click close (unpinned/pinned), OS icon rendering |
| `app/lib/widgets/port_forwarding_screen.dart` | Modify | Right-click context menu (Duplicate/Edit/Delete) on `_ForwardTile` |
| `app/test/widgets/port_forwarding_screen_test.dart` | Modify | Context-menu + duplicate tests |
| `app/test/providers/host_provider_password_test.dart` | Create | Empty-password guard tests |
| `docs/roadmap.md` | Modify | Remove shipped/obsolete polish bullets |

---

### Task 1: `os_detection.dart` pure helpers (TDD)

**Files:**
- Create: `app/test/services/os_detection_test.dart`
- Create: `app/lib/services/os_detection.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/services/os_detection_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/os_detection.dart';

void main() {
  group('parseOsReleaseId', () {
    test('unquoted ID', () {
      const content = 'NAME="Ubuntu"\nID=ubuntu\nVERSION_ID="24.04"\n';
      expect(parseOsReleaseId(content), 'ubuntu');
    });

    test('double-quoted ID', () {
      const content = 'NAME="Rocky Linux"\nID="rocky"\nID_LIKE="rhel centos fedora"\n';
      expect(parseOsReleaseId(content), 'rocky');
    });

    test('single-quoted ID', () {
      expect(parseOsReleaseId("ID='alpine'\n"), 'alpine');
    });

    test('ignores ID_LIKE and VERSION_ID', () {
      const content = 'VERSION_ID="9.3"\nID_LIKE="rhel fedora"\nID=almalinux\n';
      expect(parseOsReleaseId(content), 'almalinux');
    });

    test('missing ID returns null', () {
      expect(parseOsReleaseId('NAME="Something"\nVERSION_ID="1"\n'), isNull);
    });

    test('empty content returns null', () {
      expect(parseOsReleaseId(''), isNull);
    });

    test('uppercase value is lowercased', () {
      expect(parseOsReleaseId('ID=Ubuntu\n'), 'ubuntu');
    });
  });

  group('normalizeDistroId', () {
    test('known ids pass through', () {
      for (final id in ['ubuntu', 'debian', 'fedora', 'centos', 'rocky', 'alpine', 'arch']) {
        expect(normalizeDistroId(id), id);
      }
    });

    test('aliases map to icon keys', () {
      expect(normalizeDistroId('amzn'), 'amazon');
      expect(normalizeDistroId('almalinux'), 'alma');
      expect(normalizeDistroId('rhel'), 'redhat');
      expect(normalizeDistroId('raspbian'), 'debian');
      expect(normalizeDistroId('sles'), 'suse');
      expect(normalizeDistroId('opensuse-leap'), 'suse');
      expect(normalizeDistroId('opensuse-tumbleweed'), 'suse');
    });

    test('unknown ids fall back to linux', () {
      expect(normalizeDistroId('nixos'), 'linux');
      expect(normalizeDistroId(''), 'linux');
    });
  });

  group('osIconAsset', () {
    test('known key resolves to asset path', () {
      expect(osIconAsset('ubuntu'), 'assets/os/ubuntu.svg');
      expect(osIconAsset('macos'), 'assets/os/macos.svg');
    });

    test('null and unknown return null', () {
      expect(osIconAsset(null), isNull);
      expect(osIconAsset('beos'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/os_detection_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh/services/os_detection.dart'` (or "Target of URI doesn't exist").

- [ ] **Step 3: Write the implementation**

Create `app/lib/services/os_detection.dart`:

```dart
/// Pure helpers for distro-level OS detection and OS icon assets.
/// No Flutter/IO imports — fully unit-testable.
library;

/// detectedOs values that have a matching `assets/os/<key>.svg`.
const Set<String> kOsIconKeys = {
  'linux', 'macos', 'windows',
  'ubuntu', 'debian', 'fedora', 'centos', 'rocky', 'alma',
  'alpine', 'amazon', 'arch', 'suse', 'redhat',
};

const Map<String, String> _distroAliases = {
  'amzn': 'amazon',
  'almalinux': 'alma',
  'rhel': 'redhat',
  'raspbian': 'debian',
  'sles': 'suse',
};

/// Extracts the `ID=` value from `/etc/os-release` content
/// (e.g. `ubuntu`, `"rocky"`, `'alpine'`). Returns null when absent.
String? parseOsReleaseId(String content) {
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (!t.startsWith('ID=')) continue;
    var v = t.substring(3).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v.isEmpty ? null : v.toLowerCase();
  }
  return null;
}

/// Maps an os-release ID to an icon key in [kOsIconKeys].
/// Unknown distros fall back to generic `linux`.
String normalizeDistroId(String id) {
  final lower = id.toLowerCase();
  if (kOsIconKeys.contains(lower)) return lower;
  final alias = _distroAliases[lower];
  if (alias != null) return alias;
  if (lower.startsWith('opensuse')) return 'suse';
  return 'linux';
}

/// Asset path for a detectedOs value, or null when no icon ships for it
/// (callers keep their generic fallback, e.g. `Icons.dns`).
String? osIconAsset(String? detectedOs) =>
    detectedOs != null && kOsIconKeys.contains(detectedOs)
        ? 'assets/os/$detectedOs.svg'
        : null;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/os_detection_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/os_detection.dart app/test/services/os_detection_test.dart
git commit -m "feat(os): pure os-release parsing + OS icon asset mapping"
```

---

### Task 2: Distro SVG assets + dashboard uses the shared mapping

**Files:**
- Create: `app/assets/os/ubuntu.svg`, `debian.svg`, `fedora.svg`, `centos.svg`, `rocky.svg`, `alma.svg`, `alpine.svg`, `amazon.svg`, `arch.svg`, `suse.svg`, `redhat.svg`
- Modify: `app/lib/widgets/hosts_dashboard.dart:513-529`
- Modify: `app/test/services/os_detection_test.dart` (asset-presence guard)

Note: `pubspec.yaml` already declares the whole `assets/os/` directory — no pubspec change.
The glyphs are **intentionally simplified custom marks** in the style of the existing
`linux.svg`/`macos.svg` (24×24 viewBox, white fill, recolored at runtime via
`ColorFilter`), not reproductions of trademarked logos.

- [ ] **Step 1: Add the asset-presence test (failing)**

Append inside `main()` of `app/test/services/os_detection_test.dart`:

```dart
  group('icon assets', () {
    test('every kOsIconKeys entry has an svg on disk', () {
      // flutter test runs with cwd = app/
      for (final key in kOsIconKeys) {
        expect(File('assets/os/$key.svg').existsSync(), isTrue,
            reason: 'missing assets/os/$key.svg');
      }
    });
  });
```

Add to the imports at the top of the file:

```dart
import 'dart:io';
```

Run: `cd app && flutter test test/services/os_detection_test.dart`
Expected: FAIL — `missing assets/os/ubuntu.svg` (existing linux/macos/windows pass).

- [ ] **Step 2: Create the 11 SVGs**

`app/assets/os/ubuntu.svg` (ring + three satellites):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="4.2" fill="none" stroke="white" stroke-width="2"/>
  <circle cx="12" cy="4.2" r="2.1" fill="white"/>
  <circle cx="5.2" cy="16" r="2.1" fill="white"/>
  <circle cx="18.8" cy="16" r="2.1" fill="white"/>
</svg>
```

`app/assets/os/debian.svg` (open swirl):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="none" stroke="white" stroke-width="2" stroke-linecap="round"
        d="M16.8 9.2A6 6 0 1 0 17 14.5M14.2 10.6a3 3 0 1 0-.4 4.4"/>
</svg>
```

`app/assets/os/fedora.svg` (f in a circle):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="9" fill="none" stroke="white" stroke-width="2"/>
  <path fill="white" d="M14.5 6.5h1.5v2h-1.5c-.55 0-1 .45-1 1V11h2v2h-2v5H11v-5H9v-2h2V9.5c0-1.66 1.34-3 3.5-3z"/>
</svg>
```

`app/assets/os/centos.svg` (pinwheel of four diamonds):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="white" transform="rotate(45 12 12)">
    <rect x="4.5" y="4.5" width="6" height="6"/>
    <rect x="13.5" y="4.5" width="6" height="6"/>
    <rect x="4.5" y="13.5" width="6" height="6"/>
    <rect x="13.5" y="13.5" width="6" height="6"/>
  </g>
</svg>
```

`app/assets/os/rocky.svg` (mountain in a circle):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="9" fill="none" stroke="white" stroke-width="2"/>
  <path fill="white" d="M5.5 15.5l4.5-6 2.6 3.4 1.9-2.4 4 5z"/>
</svg>
```

`app/assets/os/alma.svg` (five-dot flower):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="12" cy="12" r="2.2" fill="white"/>
  <circle cx="12" cy="5" r="2.4" fill="white"/>
  <circle cx="18.7" cy="9.8" r="2.4" fill="white"/>
  <circle cx="16.1" cy="17.7" r="2.4" fill="white"/>
  <circle cx="7.9" cy="17.7" r="2.4" fill="white"/>
  <circle cx="5.3" cy="9.8" r="2.4" fill="white"/>
</svg>
```

`app/assets/os/alpine.svg` (twin peaks):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="white" d="M2.5 18L8 10l3.5 4.5L14 11l5.5 7z"/>
</svg>
```

`app/assets/os/amazon.svg` (cube + smile):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="none" stroke="white" stroke-width="2" d="M12 3l7.5 4.2v8.6L12 20l-7.5-4.2V7.2L12 3z"/>
  <path fill="none" stroke="white" stroke-width="2" stroke-linecap="round" d="M8.5 13.5c1.1 1.2 2.2 1.8 3.5 1.8s2.4-.6 3.5-1.8"/>
</svg>
```

`app/assets/os/arch.svg` (notched peak):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="white" d="M12 3L3.5 20h6.2c.7-1.4 1.5-2.6 2.3-3.6.8 1 1.6 2.2 2.3 3.6h6.2L12 3z"/>
</svg>
```

`app/assets/os/suse.svg` (eye + wave):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <circle cx="10" cy="9.5" r="4.5" fill="none" stroke="white" stroke-width="2"/>
  <circle cx="10" cy="9.5" r="1.7" fill="white"/>
  <path fill="none" stroke="white" stroke-width="2" stroke-linecap="round" d="M3 17.5c3 2 6 2 9 .3s6-1.7 9 .2"/>
</svg>
```

`app/assets/os/redhat.svg` (hat silhouette):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path fill="white" d="M7 12V9c0-2.76 2.24-5 5-5s5 2.24 5 5v3c1.84.62 3.1 1.66 3.46 2.9-2.3 1.42-5.2 2.1-8.46 2.1s-6.16-.68-8.46-2.1C3.9 13.66 5.16 12.62 7 12z"/>
</svg>
```

- [ ] **Step 3: Run the asset test**

Run: `cd app && flutter test test/services/os_detection_test.dart`
Expected: all PASS.

- [ ] **Step 4: Switch `hosts_dashboard.dart` to the shared mapping**

In `app/lib/widgets/hosts_dashboard.dart`, replace lines 513–529:

```dart
  static const _osAssets = {'linux', 'macos', 'windows'};

  Widget _osIcon(Host host) {
    final os = host.detectedOs;
    if (os != null && _osAssets.contains(os)) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SvgPicture.asset(
          'assets/os/$os.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return const Icon(Icons.dns, color: Colors.white, size: 18);
  }
```

with:

```dart
  Widget _osIcon(Host host) {
    final asset = osIconAsset(host.detectedOs);
    if (asset != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SvgPicture.asset(
          asset,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return const Icon(Icons.dns, color: Colors.white, size: 18);
  }
```

and add to the imports block (alongside the other `../services/` imports):

```dart
import '../services/os_detection.dart';
```

- [ ] **Step 5: Analyze + existing dashboard tests still pass**

Run: `cd app && flutter analyze && flutter test test/widgets/hosts_dashboard_menu_test.dart test/services/os_detection_test.dart`
Expected: no analyzer issues, all PASS.

- [ ] **Step 6: Commit**

```bash
git add app/assets/os app/lib/widgets/hosts_dashboard.dart app/test/services/os_detection_test.dart
git commit -m "feat(os): distro icon assets + dashboard uses shared osIconAsset mapping"
```

---

### Task 3: Distro probe in `SshService.detectOs` + re-detect gate

**Files:**
- Modify: `app/lib/services/ssh_service.dart:949-957`
- Modify: `app/lib/providers/session_provider.dart:140-145`

The parse/normalize logic is already unit-tested (Task 1); `detectOs` itself needs a live
SSH connection, so this task is wiring only (verified by analyze + manual run later).

- [ ] **Step 1: Extend `detectOs`**

In `app/lib/services/ssh_service.dart`, replace the existing method (lines 949–957):

```dart
  Future<String?> detectOs(Host host) async {
    try {
      final result = await exec(host, 'uname -s 2>/dev/null || ver');
      return parseOsFromUname(result.stdout);
    } catch (e) {
      debugPrint('[SshService] OS detect failed for ${host.host}: $e');
      return null;
    }
  }
```

with:

```dart
  Future<String?> detectOs(Host host) async {
    try {
      final result = await exec(host, 'uname -s 2>/dev/null || ver');
      final os = parseOsFromUname(result.stdout);
      if (os != 'linux') return os;
      // Linux: best-effort distro probe — generic 'linux' on any failure.
      try {
        final release = await exec(host, 'cat /etc/os-release 2>/dev/null');
        final id = parseOsReleaseId(release.stdout);
        if (id != null) return normalizeDistroId(id);
      } catch (_) {}
      return 'linux';
    } catch (e) {
      debugPrint('[SshService] OS detect failed for ${host.host}: $e');
      return null;
    }
  }
```

and add to the imports block of `ssh_service.dart`:

```dart
import 'os_detection.dart';
```

- [ ] **Step 2: Widen the re-detect gate**

In `app/lib/providers/session_provider.dart`, replace (lines 140–145):

```dart
      // Fire-and-forget: only detect if OS not yet known
      if (host.detectedOs == null) {
        _ssh.detectOs(host).then((os) {
          if (os != null) onOsDetected?.call(host.id, os);
        });
      }
```

with:

```dart
      // Fire-and-forget: detect when OS is unknown, or known only as generic
      // 'linux' (pre-distro-detection hosts upgrade to a distro id on the
      // next connect; genuinely unknown distros re-probe — one cheap exec).
      if (host.detectedOs == null || host.detectedOs == 'linux') {
        _ssh.detectOs(host).then((os) {
          if (os != null) onOsDetected?.call(host.id, os);
        });
      }
```

- [ ] **Step 3: Analyze + full service/provider tests**

Run: `cd app && flutter analyze && flutter test test/providers/ test/services/`
Expected: no analyzer issues, all PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/ssh_service.dart app/lib/providers/session_provider.dart
git commit -m "feat(os): detect Linux distro via /etc/os-release on connect"
```

---

### Task 4: Extract `SessionTab` into its own file (pure move)

**Files:**
- Create: `app/lib/widgets/session_tab.dart`
- Modify: `app/lib/screens/main_screen.dart` (remove lines 1198–1523 and 1841–1864; update usage at line 1120)

No behavior change in this task. The widget moves verbatim; only the class names gain
public visibility (`_SessionTab` → `SessionTab`, `_SessionTabState` → `_SessionTabState`
stays private in the new file).

- [ ] **Step 1: Create `app/lib/widgets/session_tab.dart`**

File skeleton — the two `// MOVED:` blocks are **verbatim copies** from
`main_screen.dart` (do not retype; cut-paste, then apply only the listed renames):

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/session_health.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/recording_provider.dart';
import '../providers/session_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../services/health_monitor_service.dart';
import '../theme/app_theme.dart';
import 'health_dot.dart';

// MOVED: main_screen.dart lines 1198–1523 (`_SessionTab` + `_SessionTabState`)
//   renames inside the moved code:
//     class _SessionTab          → class SessionTab
//     State<_SessionTab>         → State<SessionTab>
//     _SessionTabState createState() => _SessionTabState()  (unchanged)
//     const _SessionTab({...})   → const SessionTab({super.key, ...})

// MOVED: main_screen.dart lines 1841–1864 (`_healthTooltip` + `_fmtDuration`)
//   unchanged — they stay top-level private functions in this file.
```

Concretely, the moved widget declaration becomes:

```dart
class SessionTab extends StatefulWidget {
  final TerminalSession session;
  final bool isActive;
  final SessionProvider provider;
  final VoidCallback onTap;
  const SessionTab({
    super.key,
    required this.session,
    required this.isActive,
    required this.provider,
    required this.onTap,
  });

  @override
  State<SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<SessionTab> {
  // … body verbatim from main_screen.dart lines 1209–1522 …
}
```

- [ ] **Step 2: Update `main_screen.dart`**

1. Delete lines 1198–1523 (`_SessionTab` + `_SessionTabState`) and lines 1841–1864
   (`_healthTooltip`, `_fmtDuration`).
2. Add to the widget imports block:

```dart
import '../widgets/session_tab.dart';
```

3. At the usage site (line ~1120), rename:

```dart
                  child: _SessionTab(
```

to:

```dart
                  child: SessionTab(
```

4. Remove imports that become unused (run `flutter analyze` to find them —
   likely candidates: `package:path/path.dart`, `health_dot.dart`,
   `../models/session_health.dart`; keep any the analyzer still wants).

- [ ] **Step 3: Analyze + full test suite (pure-move safety net)**

Run: `cd app && flutter analyze && flutter test`
Expected: no analyzer issues, all PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/session_tab.dart app/lib/screens/main_screen.dart
git commit -m "refactor(ui): extract SessionTab widget out of main_screen"
```

---

### Task 5: Middle-click closes unpinned tabs (TDD)

**Files:**
- Create: `app/test/widgets/session_tab_test.dart`
- Modify: `app/lib/widgets/session_tab.dart` (the GestureDetector in `build`)

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/session_tab_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/health_monitor_service.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/session_tab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  (SessionProvider, HostProvider) makeProviders() {
    final storage = StorageService();
    final sessions = SessionProvider(SshService(storage), TabMetadataService());
    final hosts = HostProvider(storage);
    return (sessions, hosts);
  }

  Widget wrap(Widget tab, SessionProvider sessions, HostProvider hosts) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: sessions),
        ChangeNotifierProvider.value(value: hosts),
        ChangeNotifierProvider(create: (_) => ShellIntegrationProvider()),
        ChangeNotifierProvider(
            create: (_) =>
                RecordingProvider(RecordingService(), getPath: () => '/tmp')),
        ChangeNotifierProvider(
            create: (_) => HealthMonitorService(
                measure: (_) async => null,
                connectedHostIds: () => const <String>[],
                pollSeconds: () => 0)),
      ],
      child: MaterialApp(home: Scaffold(body: Row(children: [tab]))),
    );
  }

  SshSession seedSession(SessionProvider sessions, Host host,
      {bool pinned = false}) {
    final session = SshSession(
        host: host, status: SessionStatus.connected, isPinned: pinned);
    sessions.sessions.add(session);
    return session;
  }

  Future<void> middleClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kTertiaryButton);
    await gesture.down(tester.getCenter(finder));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  final host =
      Host(id: 'h1', label: 'prod', host: '1.2.3.4', port: 22, username: 'u');

  testWidgets('middle-click closes an unpinned tab', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    await middleClick(tester, find.byType(SessionTab));
    expect(sessions.sessions, isEmpty);
  });

  testWidgets('middle-click is ignored on a pinned tab', (tester) async {
    final (sessions, hosts) = makeProviders();
    final session = seedSession(sessions, host, pinned: true);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    await middleClick(tester, find.byType(SessionTab));
    expect(sessions.sessions, hasLength(1));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/session_tab_test.dart`
Expected: first test FAILS (`Expected: empty, Actual: [Instance of 'SshSession']`) —
middle-click does nothing yet. Second test passes (nothing happens on pinned either way).

- [ ] **Step 3: Add the middle-click handler**

In `app/lib/widgets/session_tab.dart`, in `build`, the GestureDetector currently reads:

```dart
      child: GestureDetector(
        onTap: () {
          widget.provider.setActive(widget.session.id);
          widget.onTap();
        },
        onDoubleTap: _startRename,
        onSecondaryTapUp: (details) =>
            _showTabContextMenu(context, details.globalPosition),
```

Add the tertiary handler after `onSecondaryTapUp`:

```dart
        // Middle-click closes the tab; pinned tabs are protected (consistent
        // with the hidden X button — close stays reachable via the menu).
        onTertiaryTapUp: widget.session.isPinned
            ? null
            : (_) => widget.provider.closeSession(widget.session.id),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/session_tab_test.dart`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/session_tab.dart app/test/widgets/session_tab_test.dart
git commit -m "feat(tabs): middle-click closes unpinned session tabs"
```

---

### Task 6: OS icon on session tabs (TDD)

**Files:**
- Modify: `app/test/widgets/session_tab_test.dart`
- Modify: `app/lib/widgets/session_tab.dart`

- [ ] **Step 1: Write the failing tests**

Append to `main()` in `app/test/widgets/session_tab_test.dart`:

```dart
  testWidgets('shows distro icon when the host has a detectedOs',
      (tester) async {
    final (sessions, hosts) = makeProviders();
    final ubuntuHost = Host(
        id: 'h2',
        label: 'web',
        host: '5.6.7.8',
        port: 22,
        username: 'u',
        detectedOs: 'ubuntu');
    await hosts.addHost(ubuntuHost);
    final session = seedSession(sessions, ubuntuHost);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    expect(
        find.byWidgetPredicate((w) =>
            w is SvgPicture &&
            (w.bytesLoader as SvgAssetLoader).assetName ==
                'assets/os/ubuntu.svg'),
        findsOneWidget);
  });

  testWidgets('no OS icon when detectedOs is unknown', (tester) async {
    final (sessions, hosts) = makeProviders();
    await hosts.addHost(host); // detectedOs == null
    final session = seedSession(sessions, host);

    await tester.pumpWidget(wrap(
        SessionTab(
            session: session,
            isActive: true,
            provider: sessions,
            onTap: () {}),
        sessions,
        hosts));

    expect(find.byType(SvgPicture), findsNothing);
  });
```

Add the import at the top of the test file:

```dart
import 'package:flutter_svg/flutter_svg.dart';
```

(Verified: the `Host` constructor accepts `detectedOs` — `host.dart:41`.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/session_tab_test.dart`
Expected: new first test FAILS (`findsOneWidget` → found 0). Second passes vacuously.

- [ ] **Step 3: Render the icon in `SessionTab`**

In `app/lib/widgets/session_tab.dart` `build`, the Row starts with the health-dot block:

```dart
              if (widget.session case final SshSession ssh
                  when !ssh.isWatch)
                Builder(builder: (context) {
                  final health = context
                      .watch<HealthMonitorService>()
                      .healthFor(ssh.host.id);
                  ...
                })
              else if (widget.session.isLocal)
                ...
```

Insert a new block **immediately after** that if/else chain (before the recording
indicator `Consumer<RecordingProvider>`):

```dart
              // Distro/OS glyph — reads detectedOs from HostProvider (the
              // session's Host snapshot goes stale after copyWith on detect).
              if (widget.session case final SshSession ssh when !ssh.isWatch)
                Builder(builder: (context) {
                  final os = context.select<HostProvider, String?>((hp) {
                    for (final h in hp.allHosts) {
                      if (h.id == ssh.host.id) return h.detectedOs;
                    }
                    return null;
                  });
                  final asset = osIconAsset(os);
                  if (asset == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: SvgPicture.asset(
                      asset,
                      width: 14,
                      height: 14,
                      colorFilter: const ColorFilter.mode(
                          Color(0xFF888888), BlendMode.srcIn),
                    ),
                  );
                }),
```

Add the imports to `session_tab.dart`:

```dart
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/host_provider.dart';
import '../services/os_detection.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/session_tab_test.dart`
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/session_tab.dart app/test/widgets/session_tab_test.dart
git commit -m "feat(tabs): show distro/OS icon on SSH session tabs"
```

---

### Task 7: Duplicate port-forward rule via context menu (TDD)

**Files:**
- Modify: `app/test/widgets/port_forwarding_screen_test.dart`
- Modify: `app/lib/widgets/port_forwarding_screen.dart` (`_ForwardTile`, lines 132–247)

- [ ] **Step 1: Write the failing tests**

Append to `main()` in `app/test/widgets/port_forwarding_screen_test.dart`:

```dart
  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await gesture.down(tester.getCenter(finder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-click opens context menu with Duplicate/Edit/Delete',
      (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'menu me',
        type: ForwardType.local,
        localPort: 7000,
        remoteHost: 'db',
        remotePort: 5432));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('menu me'));

    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Duplicate adds a copy with new id, "(copy)" label, autoStart off',
      (tester) async {
    final (provider, widget) = await build();
    final original = PortForward(
        label: 'db tunnel',
        type: ForwardType.local,
        localHost: '127.0.0.1',
        localPort: 8080,
        remoteHost: 'db.internal',
        remotePort: 5432,
        hostId: 'h1',
        autoStart: true);
    await provider.add(original);

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('db tunnel'));
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(provider.forwards, hasLength(2));
    final copy =
        provider.forwards.firstWhere((f) => f.id != original.id);
    expect(copy.label, 'db tunnel (copy)');
    expect(copy.type, original.type);
    expect(copy.localHost, original.localHost);
    expect(copy.localPort, original.localPort);
    expect(copy.remoteHost, original.remoteHost);
    expect(copy.remotePort, original.remotePort);
    expect(copy.hostId, original.hostId);
    expect(copy.autoStart, isFalse);
    expect(copy.status, ForwardStatus.idle);
  });

  testWidgets('Edit menu entry opens the edit panel', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'edit via menu',
        type: ForwardType.local,
        localPort: 9001,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('edit via menu'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
  });

  testWidgets('Delete menu entry removes the rule', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'delete via menu',
        type: ForwardType.local,
        localPort: 9002,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('delete via menu'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(provider.forwards, isEmpty);
  });
```

Add the import at the top of the test file:

```dart
import 'package:flutter/gestures.dart';
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/port_forwarding_screen_test.dart`
Expected: the 4 new tests FAIL (`find.text('Duplicate')` finds nothing — no context menu yet).

- [ ] **Step 3: Implement the context menu**

In `app/lib/widgets/port_forwarding_screen.dart`, add methods to `_ForwardTileState`
(before `build`):

```dart
  Future<void> _duplicate() async {
    final fwd = widget.forward;
    await context.read<PortForwardProvider>().add(PortForward(
          label: '${fwd.label} (copy)',
          type: fwd.type,
          localHost: fwd.localHost,
          localPort: fwd.localPort,
          remoteHost: fwd.remoteHost,
          remotePort: fwd.remotePort,
          hostId: fwd.hostId,
          autoStart: false, // a copy must never race the original on launch
        ));
  }

  Future<void> _delete() async {
    final service = context.read<PortForwardService>();
    final provider = context.read<PortForwardProvider>();
    await service.stop(widget.forward.id);
    await provider.delete(widget.forward.id);
  }

  Future<void> _showContextMenu(Offset globalPos) async {
    PopupMenuItem<String> item(String value, IconData icon, String label,
        {Color color = const Color(0xFFCCCCCC)}) {
      return PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 14, color: const Color(0xFFAAAAAA)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ]),
      );
    }

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        item('duplicate', Icons.copy_outlined, 'Duplicate'),
        item('edit', Icons.edit_outlined, 'Edit'),
        const PopupMenuDivider(),
        item('delete', Icons.delete_outlined, 'Delete', color: AppColors.red),
      ],
    );
    if (!mounted) return;

    switch (result) {
      case 'duplicate':
        await _duplicate();
      case 'edit':
        widget.onEdit(widget.forward);
      case 'delete':
        await _delete();
    }
  }
```

Then wire it on the tile's GestureDetector (line ~160):

```dart
      child: GestureDetector(
        onTap: () => widget.onEdit(fwd),
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/port_forwarding_screen_test.dart`
Expected: all PASS (2 pre-existing + 4 new).

Note: `_delete` calls `PortForwardService.stop`, which no-ops for a tunnel that was
never started — same as the existing hover-delete path. If the Delete test throws from
the fake transport, the bug is in the new code, not the fake.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/port_forwarding_screen.dart app/test/widgets/port_forwarding_screen_test.dart
git commit -m "feat(pf): right-click context menu with Duplicate on port-forward rules"
```

---

### Task 8: Empty-password behavior tests

**Files:**
- Create: `app/test/providers/host_provider_password_test.dart`

These tests document existing behavior and must pass **without** production changes.
If any fails, stop and report — that would falsify the spec's assumption.

- [ ] **Step 1: Write the tests**

Create `app/test/providers/host_provider_password_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

/// Locks in empty-password SSH support: a blank password is never persisted
/// (so `loadPassword` stays null) and the connect path sends '' to the server
/// via `onPasswordRequest: () => password ?? ''` in SshService.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late HostProvider provider;
  final host =
      Host(id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    provider = HostProvider(storage);
  });

  test('addHost with empty password saves nothing', () async {
    await provider.addHost(host, password: '');
    expect(await storage.loadPassword('h1'), isNull);
  });

  test('addHost with null password saves nothing', () async {
    await provider.addHost(host);
    expect(await storage.loadPassword('h1'), isNull);
  });

  test('addHost with a real password persists it', () async {
    await provider.addHost(host, password: 's3cret');
    expect(await storage.loadPassword('h1'), 's3cret');
  });

  test('updateHost with empty password keeps the stored one', () async {
    await provider.addHost(host, password: 's3cret');
    await provider.updateHost(host, password: '');
    expect(await storage.loadPassword('h1'), 's3cret');
  });
}
```

- [ ] **Step 2: Run — expect immediate PASS**

Run: `cd app && flutter test test/providers/host_provider_password_test.dart`
Expected: all 4 PASS with no production change. (In tests, secure storage has no
platform channel, so `StorageService` falls through to its SharedPreferences path —
that fallback is part of the production design.)

- [ ] **Step 3: Commit**

```bash
git add app/test/providers/host_provider_password_test.dart
git commit -m "test(auth): lock in empty-password SSH behavior"
```

---

### Task 9: Roadmap + final verification

**Files:**
- Modify: `docs/roadmap.md`

- [ ] **Step 1: Update the roadmap polish list**

In `docs/roadmap.md` → "### Polish existing features", delete these three bullets
(now shipped by this bundle):

```markdown
- Port forwarding: duplicate-rule action on the rule list.
- Tabs: middle-click closes a tab.
- Auth: allow empty-password SSH (some appliances/lab boxes).
```

and replace the host-OS-icons bullet:

```markdown
- Host OS icons: map the existing `detectedOs` to distro icons (Ubuntu/Debian/Rocky/Alpine/Amazon…) on the host list and session tabs.
```

with nothing (also shipped). Then append to the end of the "Already shipped" paragraph
(before the final period):

```
, **Quick wins (0.1.29)** — middle-click closes unpinned session tabs; right-click context menu on port-forward rules with Duplicate (new id, "(copy)" label, auto-start off); distro-level OS icons (`/etc/os-release` ID → ubuntu/debian/fedora/centos/rocky/alma/alpine/amazon/arch/suse/redhat glyphs) on the hosts dashboard and SSH session tabs (`os_detection.dart`, `SessionTab` extracted from main_screen); empty-password SSH behavior locked in by tests (blank passwords are never persisted; connect sends '')
```

(If the release ends up with a different version number, use that instead of 0.1.29.)

- [ ] **Step 2: Full verification**

Run: `cd app && flutter analyze && flutter test`
Expected: zero analyzer issues, full suite PASS.

- [ ] **Step 3: Manual smoke check (macOS)**

Run: `cd app && flutter run -d macos`
- Connect to a Linux host → host card + session tab show the distro glyph after a moment
  (re-detect upgrades old generic-linux hosts).
- Middle-click an unpinned tab → closes. Pin a tab (right-click → Pin) → middle-click does nothing.
- Port Forwarding → right-click a rule → Duplicate → "<label> (copy)" appears, stopped, auto-start off.

- [ ] **Step 4: Commit**

```bash
git add docs/roadmap.md
git commit -m "docs(roadmap): quick wins bundle shipped"
```

---

## Self-review notes

- Spec §1 → Task 5; §2 → Task 7; §3 → Tasks 1–4 + 6; §4 → Task 8 + Task 9 roadmap edit. Wiki updates happen at release time per the release workflow, not in this plan.
- `SessionTab` extraction (Task 4) is the enabler for testing Tasks 5–6; it is a pure move with the full suite as a safety net.
- Type consistency: `osIconAsset(String?) → String?` used in Tasks 2 and 6; `parseOsReleaseId`/`normalizeDistroId` defined in Task 1, consumed in Task 3 exactly as declared.
