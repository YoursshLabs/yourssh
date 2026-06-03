# SFTP View + Open With Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only "View" mode to `CodeEditorScreen` and replace "Open with external app" with a platform-aware "Open with ▶" submenu that lists installed apps (macOS via Swift method channel, Linux via `.desktop` file parsing, Windows via PowerShell registry query) plus a "Choose…" file-picker fallback.

**Architecture:** `AppDiscoveryService` provides `getAppsFor(filePath)` with per-extension caching; the macOS implementation calls a new Flutter method channel registered in `AppDelegate.swift`; Linux scans `.desktop` files in Dart; Windows uses PowerShell. `ExternalEditService` gains `openExternalWith(host, entry, appPath)` to launch a specific app instead of the OS default. `SftpEntryContextMenu` replaces `onOpenExternal` with `onOpenWith` and renders a second `showMenu` call as a submenu. `CodeEditorScreen` gains `readOnly: bool`.

**Tech Stack:** Flutter (desktop), provider, `file_selector: ^0.9.0` (new dep), Swift (macOS AppDelegate), Dart process interop (Linux/Windows).

**Spec:** `docs/superpowers/specs/2026-06-03-sftp-view-openwith-design.md`

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/models/app_option.dart` | **Create** | `AppOption` data class |
| `app/lib/services/app_discovery_service.dart` | **Create** | Per-platform app discovery + cache |
| `app/macos/Runner/AppDelegate.swift` | **Modify** | Register `yourssh/app_discovery` method channel |
| `app/assets/monaco_editor.html` | **Modify** | Add `setReadOnly(bool)` JS function |
| `app/lib/widgets/code_editor_screen.dart` | **Modify** | `readOnly` param, lock-icon AppBar, read-only TextField/webview |
| `app/lib/services/external_edit_service.dart` | **Modify** | Add `openExternalWith(host, entry, appPath)` |
| `app/lib/widgets/sftp_entry_context_menu.dart` | **Modify** | Replace `onOpenExternal` → `onOpenWith`; add View action; submenu |
| `app/lib/widgets/sftp_panel.dart` | **Modify** | Wire new callbacks; inject `AppDiscoveryService` |
| `app/lib/widgets/dual_panel_sftp_screen.dart` | **Modify** | Register `AppDiscoveryService` in MultiProvider |
| `app/pubspec.yaml` | **Modify** | Add `file_selector: ^0.9.0` |
| `app/test/models/app_option_test.dart` | **Create** | `AppOption` equality / JSON round-trip |
| `app/test/services/app_discovery_service_linux_test.dart` | **Create** | Linux `.desktop` parsing with fixture files |
| `app/test/services/app_discovery_service_test.dart` | **Create** | Cache behaviour + error handling |
| `app/test/services/external_edit_service_test.dart` | **Modify** | Add `openExternalWith` test |
| `app/test/widgets/code_editor_screen_fallback_test.dart` | **Modify** | Add `readOnly: true` tests |
| `app/test/widgets/sftp_entry_context_menu_test.dart` | **Modify** | New View action + onOpenWith callback |
| `CHANGELOG.md` | **Modify** | Add Unreleased entries |
| `CLAUDE.md` | **Modify** | Add `AppDiscoveryService` to services list |

---

### Task 1: `AppOption` data class

**Files:**
- Create: `app/lib/models/app_option.dart`
- Test: `app/test/models/app_option_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/app_option_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';

void main() {
  test('AppOption stores fields correctly', () {
    const opt = AppOption(
      name: 'VS Code',
      executablePath: '/Applications/Visual Studio Code.app',
      iconPath: '/Applications/Visual Studio Code.app/Contents/Resources/Code.icns',
      isDefault: true,
    );
    expect(opt.name, 'VS Code');
    expect(opt.executablePath, '/Applications/Visual Studio Code.app');
    expect(opt.iconPath,
        '/Applications/Visual Studio Code.app/Contents/Resources/Code.icns');
    expect(opt.isDefault, isTrue);
  });

  test('AppOption with null iconPath', () {
    const opt = AppOption(
      name: 'gedit',
      executablePath: '/usr/bin/gedit',
      isDefault: false,
    );
    expect(opt.iconPath, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/app_option_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh/models/app_option.dart'`

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/models/app_option.dart
class AppOption {
  const AppOption({
    required this.name,
    required this.executablePath,
    this.iconPath,
    required this.isDefault,
  });

  final String name;
  final String executablePath;
  final String? iconPath;
  final bool isDefault;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/app_option_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/app_option.dart app/test/models/app_option_test.dart
git commit -m "feat(sftp): AppOption model"
```

---

### Task 2: `AppDiscoveryService` — Linux `.desktop` parser

**Files:**
- Create: `app/lib/services/app_discovery_service.dart`
- Test: `app/test/services/app_discovery_service_linux_test.dart`
- Test: `app/test/services/app_discovery_service_test.dart`
- Create fixture: `app/test/fixtures/applications/gedit.desktop`
- Create fixture: `app/test/fixtures/applications/eog.desktop`

The Linux path is pure Dart and can run on any platform, making it fully unit-testable. macOS and Windows paths use process/channel calls that are stubbed in tests.

- [ ] **Step 1: Create fixture `.desktop` files**

```ini
# app/test/fixtures/applications/gedit.desktop
[Desktop Entry]
Name=Text Editor
Exec=gedit %F
MimeType=text/plain;text/x-diff;
Type=Application
```

```ini
# app/test/fixtures/applications/eog.desktop
[Desktop Entry]
Name=Image Viewer
Exec=eog %U
MimeType=image/png;image/jpeg;
Type=Application
```

- [ ] **Step 2: Write failing tests**

```dart
// app/test/services/app_discovery_service_linux_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/services/app_discovery_service.dart';

void main() {
  late Directory fixtureDir;

  setUpAll(() {
    fixtureDir = Directory('test/fixtures/applications');
  });

  test('parseDesktopFiles returns apps matching the MIME type', () {
    final apps = AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: 'gedit.desktop',
    );
    expect(apps.map((a) => a.name), contains('Text Editor'));
    expect(apps.map((a) => a.name), isNot(contains('Image Viewer')));
    expect(apps.first.isDefault, isTrue);
  });

  test('parseDesktopFiles strips Exec placeholders', () {
    final apps = AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: '',
    );
    final gedit = apps.firstWhere((a) => a.name == 'Text Editor');
    expect(gedit.executablePath, 'gedit');
    expect(gedit.executablePath, isNot(contains('%')));
  });

  test('parseDesktopFiles returns empty list when no MIME match', () {
    final apps = AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'application/pdf',
      defaultDesktopFile: '',
    );
    expect(apps, isEmpty);
  });

  test('parseDesktopFiles ignores malformed desktop files gracefully', () {
    final tmp = File('${fixtureDir.path}/broken.desktop')
      ..writeAsStringSync('not valid content at all');
    addTearDown(tmp.deleteSync);

    final apps = AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: '',
    );
    expect(apps.map((a) => a.name), contains('Text Editor'));
  });
}
```

```dart
// app/test/services/app_discovery_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/services/app_discovery_service.dart';

void main() {
  test('cache returns same list on second call without re-querying', () async {
    var queryCalls = 0;
    final service = AppDiscoveryService.withQuerier((_) async {
      queryCalls++;
      return [
        const AppOption(
            name: 'Test App',
            executablePath: '/usr/bin/test',
            isDefault: false),
      ];
    });

    final first = await service.getAppsFor('/tmp/foo.txt');
    final second = await service.getAppsFor('/tmp/bar.txt');

    expect(queryCalls, 1); // both .txt → same extension → cached
    expect(first, same(second));
    service.dispose();
  });

  test('cache is cleared on dispose', () async {
    var queryCalls = 0;
    final service = AppDiscoveryService.withQuerier((_) async {
      queryCalls++;
      return [];
    });

    await service.getAppsFor('/tmp/foo.txt');
    service.dispose();
    await service.getAppsFor('/tmp/foo.txt');

    expect(queryCalls, 2);
    service.dispose();
  });

  test('returns empty list when querier throws', () async {
    final service = AppDiscoveryService.withQuerier(
        (_) async => throw Exception('platform error'));

    final apps = await service.getAppsFor('/tmp/foo.txt');
    expect(apps, isEmpty);
    service.dispose();
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd app && flutter test test/services/app_discovery_service_linux_test.dart test/services/app_discovery_service_test.dart`
Expected: FAIL — file not found

- [ ] **Step 4: Write the implementation**

```dart
// app/lib/services/app_discovery_service.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../models/app_option.dart';

typedef _Querier = Future<List<AppOption>> Function(String filePath);

/// Discovers applications that can open a given file, filtered by the file's
/// MIME type / extension. Results are cached per file extension.
class AppDiscoveryService {
  AppDiscoveryService() : _querier = _defaultQuerier;

  /// Test-only constructor: inject a custom querier to avoid real process calls.
  AppDiscoveryService.withQuerier(this._querier);

  final _Querier _querier;
  final _cache = <String, List<AppOption>>{};

  /// Returns apps that can open [filePath], cached by extension.
  /// Never throws — returns [] on any platform error.
  Future<List<AppOption>> getAppsFor(String filePath) async {
    final ext = p.extension(filePath).toLowerCase(); // e.g. ".txt"
    if (_cache.containsKey(ext)) return _cache[ext]!;
    try {
      final apps = await _querier(filePath);
      _cache[ext] = apps;
      return apps;
    } catch (_) {
      return [];
    }
  }

  void dispose() => _cache.clear();

  // ── Platform implementations ──────────────────────────────────────────────

  static Future<List<AppOption>> _defaultQuerier(String filePath) {
    if (Platform.isMacOS) return _queryMacOS(filePath);
    if (Platform.isLinux) return _queryLinux(filePath);
    if (Platform.isWindows) return _queryWindows(filePath);
    return Future.value([]);
  }

  // ── macOS ─────────────────────────────────────────────────────────────────

  static const _channel = MethodChannel('yourssh/app_discovery');

  static Future<List<AppOption>> _queryMacOS(String filePath) async {
    final raw = await _channel.invokeListMethod<List<Object?>>('getAppsFor', {'path': filePath});
    if (raw == null) return [];
    return raw.map((entry) {
      final list = entry.cast<String>();
      return AppOption(
        name: list[0],
        executablePath: list[2],
        iconPath: list[3].isEmpty ? null : list[3],
        isDefault: false, // macOS doesn't single out a default via this API
      );
    }).toList();
  }

  // ── Linux ─────────────────────────────────────────────────────────────────

  static Future<List<AppOption>> _queryLinux(String filePath) async {
    final mimeResult = await Process.run('xdg-mime', ['query', 'filetype', filePath]);
    if (mimeResult.exitCode != 0) return [];
    final mimeType = (mimeResult.stdout as String).trim();

    final defaultResult =
        await Process.run('xdg-mime', ['query', 'default', mimeType]);
    final defaultFile = (defaultResult.stdout as String).trim();

    final dirs = [
      Directory(p.join(Platform.environment['HOME'] ?? '', '.local', 'share', 'applications')),
      Directory('/usr/share/applications'),
      Directory('/usr/local/share/applications'),
    ];

    final files = <File>[];
    for (final dir in dirs) {
      if (dir.existsSync()) {
        files.addAll(dir.listSync().whereType<File>()
            .where((f) => f.path.endsWith('.desktop')));
      }
    }

    return parseDesktopFiles(
        files: files, mimeType: mimeType, defaultDesktopFile: defaultFile);
  }

  /// Pure function exposed for unit testing without touching the filesystem.
  static List<AppOption> parseDesktopFiles({
    required List<File> files,
    required String mimeType,
    required String defaultDesktopFile,
  }) {
    final result = <AppOption>[];
    for (final file in files) {
      try {
        final lines = file.readAsLinesSync();
        String? name, exec, mimeTypes;
        for (final line in lines) {
          if (line.startsWith('Name=') && name == null) name = line.substring(5).trim();
          if (line.startsWith('Exec=')) exec = line.substring(5).trim();
          if (line.startsWith('MimeType=')) mimeTypes = line.substring(9).trim();
        }
        if (name == null || exec == null || mimeTypes == null) continue;
        if (!mimeTypes.split(';').map((s) => s.trim()).contains(mimeType)) continue;

        // Strip Exec placeholders (%f, %F, %u, %U, %i, %c, %k)
        final cleanExec = exec.replaceAll(RegExp(r'\s*%[fFuUick]\s*'), '').trim();
        final execBin = cleanExec.split(' ').first;

        result.add(AppOption(
          name: name,
          executablePath: execBin,
          isDefault: p.basename(file.path) == defaultDesktopFile,
        ));
      } catch (_) {
        continue; // skip malformed .desktop files
      }
    }
    return result;
  }

  // ── Windows ───────────────────────────────────────────────────────────────

  static Future<List<AppOption>> _queryWindows(String filePath) async {
    final ext = p.extension(filePath); // e.g. ".txt"
    // Query OpenWithList from user-specific registry key
    final psScript = '''
\$ext = '$ext';
\$key = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\\$ext\\OpenWithList";
\$props = Get-ItemProperty \$key -ErrorAction SilentlyContinue;
if (\$props -eq \$null) { exit 0 }
\$props.PSObject.Properties | Where-Object { \$_.Name -match '^[a-zA-Z]\$' } | ForEach-Object { \$_.Value }
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', psScript],
    );
    if (result.exitCode != 0) return await _queryWindowsFallback(ext);

    final exeNames = (result.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.endsWith('.exe'))
        .toList();

    if (exeNames.isEmpty) return await _queryWindowsFallback(ext);

    final apps = <AppOption>[];
    for (final exeName in exeNames) {
      final whereResult =
          await Process.run('where', [exeName], runInShell: true);
      final path = (whereResult.stdout as String).split('\n').first.trim();
      if (path.isEmpty || !File(path).existsSync()) continue;

      final descScript =
          '[System.Diagnostics.FileVersionInfo]::GetVersionInfo("$path").FileDescription';
      final descResult = await Process.run(
          'powershell', ['-NoProfile', '-Command', descScript]);
      final desc = (descResult.stdout as String).trim();
      apps.add(AppOption(
        name: desc.isNotEmpty ? desc : exeName.replaceAll('.exe', ''),
        executablePath: path,
        isDefault: false,
      ));
    }
    return apps;
  }

  // Fallback: read the default handler via `assoc` + `ftype`
  static Future<List<AppOption>> _queryWindowsFallback(String ext) async {
    final assocResult =
        await Process.run('cmd', ['/c', 'assoc', ext], runInShell: true);
    if (assocResult.exitCode != 0) return [];
    final progId = (assocResult.stdout as String)
        .split('=')
        .skip(1)
        .join('=')
        .trim();
    if (progId.isEmpty) return [];

    final ftypeResult =
        await Process.run('cmd', ['/c', 'ftype', progId], runInShell: true);
    if (ftypeResult.exitCode != 0) return [];
    final ftypeLine = (ftypeResult.stdout as String).split('=').skip(1).join('=').trim();
    final exePath = ftypeLine.split('"').where((s) => s.endsWith('.exe')).firstOrNull;
    if (exePath == null) return [];

    return [
      AppOption(
        name: progId,
        executablePath: exePath,
        isDefault: true,
      )
    ];
  }
}
```

- [ ] **Step 5: Create the fixture directories**

```bash
mkdir -p app/test/fixtures/applications
```

Create `app/test/fixtures/applications/gedit.desktop`:
```ini
[Desktop Entry]
Name=Text Editor
Exec=gedit %F
MimeType=text/plain;text/x-diff;
Type=Application
```

Create `app/test/fixtures/applications/eog.desktop`:
```ini
[Desktop Entry]
Name=Image Viewer
Exec=eog %U
MimeType=image/png;image/jpeg;
Type=Application
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd app && flutter test test/services/app_discovery_service_linux_test.dart test/services/app_discovery_service_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 7: Commit**

```bash
git add app/lib/services/app_discovery_service.dart app/lib/models/app_option.dart \
        app/test/services/app_discovery_service_linux_test.dart \
        app/test/services/app_discovery_service_test.dart \
        app/test/fixtures/
git commit -m "feat(sftp): AppDiscoveryService with Linux .desktop parser and cache"
```

---

### Task 3: macOS Swift method channel

**Files:**
- Modify: `app/macos/Runner/AppDelegate.swift`

No Dart unit tests for this task (it's Swift calling macOS APIs). The Dart side gracefully handles a missing or erroring channel (returns `[]`).

- [ ] **Step 1: Register the method channel in AppDelegate.swift**

Replace the full content of `app/macos/Runner/AppDelegate.swift` with:

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController
            as? FlutterViewController else { return }

    let channel = FlutterMethodChannel(
      name: "yourssh/app_discovery",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      guard call.method == "getAppsFor",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let fileURL = URL(fileURLWithPath: path)
      let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
      let mapped: [[String]] = apps.map { appURL in
        let bundle = Bundle(url: appURL)
        let name = bundle?.infoDictionary?["CFBundleName"] as? String
          ?? appURL.deletingPathExtension().lastPathComponent
        let bundleId = bundle?.bundleIdentifier ?? ""
        var iconPath = ""
        if let resourceURL = bundle?.resourceURL,
           let iconFile = bundle?.infoDictionary?["CFBundleIconFile"] as? String {
          var icon = iconFile
          if !icon.hasSuffix(".icns") { icon += ".icns" }
          iconPath = resourceURL.appendingPathComponent(icon).path
        }
        return [name, bundleId, appURL.path, iconPath]
      }
      result(mapped)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication) -> Bool { return true }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication) -> Bool { return true }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `cd app && flutter build macos --debug 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED` (no Swift compiler errors)

- [ ] **Step 3: Commit**

```bash
git add app/macos/Runner/AppDelegate.swift
git commit -m "feat(sftp): macOS method channel for app discovery (NSWorkspace)"
```

---

### Task 4: Add `file_selector` dependency

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `app/pubspec.yaml`, under `dependencies:`, add:
```yaml
  file_selector: ^0.9.0
```

- [ ] **Step 2: Fetch packages**

Run: `cd app && flutter pub get`
Expected: exit 0, `file_selector` appears in `pubspec.lock`

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "chore: add file_selector dependency"
```

---

### Task 5: `ExternalEditService.openExternalWith`

**Files:**
- Modify: `app/lib/services/external_edit_service.dart`
- Modify: `app/test/services/external_edit_service_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the existing `external_edit_service_test.dart`, inside `main()`, after the existing tests:

```dart
  test('openExternalWith launches with the specified app path', () async {
    final launched = <(Uri, String?)>[];
    final serviceWithApp = ExternalEditService(
      transfer,
      appLauncher: (uri, appPath) async {
        launched.add((uri, appPath));
        return true;
      },
      pollInterval: const Duration(milliseconds: 30),
    );
    addTearDown(serviceWithApp.dispose);

    await serviceWithApp.openExternalWith(_host, _entry, '/Applications/TextEdit.app');

    expect(launched, hasLength(1));
    expect(launched.first.$2, '/Applications/TextEdit.app');
  });
```

Also update the existing `setUp` in that file: the `launcher:` named parameter will become `appLauncher:` in the new signature, but we keep backward compat — add an `appLauncher` param that defaults to `null` and falls back to calling `_launch` (the existing `Uri`-only launcher). To avoid breaking the existing tests, keep `launcher:` working (see implementation step below).

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd app && flutter test test/services/external_edit_service_test.dart`
Expected: FAIL — `No named parameter with the name 'appLauncher'`

- [ ] **Step 3: Update `ExternalEditService`**

Add a new typedef and an optional secondary launcher. The changes to `external_edit_service.dart`:

1. Add typedef after the existing `ExternalLauncher` typedef:
```dart
typedef AppLauncher = Future<bool> Function(Uri uri, String? appPath);
```

2. Add `appLauncher` optional param to the constructor (keeping `launcher` for back-compat):
```dart
class ExternalEditService {
  ExternalEditService(
    this._transferService, {
    ExternalLauncher? launcher,
    AppLauncher? appLauncher,
    this.pollInterval = const Duration(seconds: 2),
  })  : _launch = launcher ?? launchUrl,
        _appLaunch = appLauncher;
```

3. Add field:
```dart
  final AppLauncher? _appLaunch;
```

4. Add `openExternalWith` method (after `openExternal`):
```dart
  /// Like [openExternal] but launches with a specific application [appPath]
  /// instead of the OS default.
  Future<void> openExternalWith(
      Host host, SftpEntry entry, String appPath) async {
    final localFile = await _prepareLocalFile(host, entry);
    final launched = await _launchWithApp(localFile.path, appPath);
    if (!launched) {
      throw ExternalEditException(
          'Failed to open ${entry.name} with $appPath');
    }
    _startWatcher(host, entry, localFile);
  }
```

5. Refactor `openExternal` to use the same helpers. Replace `openExternal` body:
```dart
  Future<void> openExternal(Host host, SftpEntry entry) async {
    final localFile = await _prepareLocalFile(host, entry);
    final launched = _appLaunch != null
        ? await _appLaunch!(Uri.file(localFile.path), null)
        : await _launch(Uri.file(localFile.path));
    if (!launched) {
      throw ExternalEditException('No application found to open ${entry.name}');
    }
    _startWatcher(host, entry, localFile);
  }
```

6. Add the two private helpers (extracted from old `openExternal`):
```dart
  Future<File> _prepareLocalFile(Host host, SftpEntry entry) async {
    final tmpPath = await _transferService.downloadToTemp(host, entry);
    if (tmpPath == null) {
      throw ExternalEditException('Download failed for ${entry.name}');
    }
    final sessionDir = Directory(
        '${File(tmpPath).parent.path}/yourssh_edit/${_sessionCounter++}');
    await sessionDir.create(recursive: true);
    return File(tmpPath).rename('${sessionDir.path}/${entry.name}');
  }

  void _startWatcher(Host host, SftpEntry entry, File localFile) {
    final session = _WatchSession(
      host: host,
      entry: entry,
      file: localFile,
      lastModified: localFile.lastModifiedSync(),
    );
    session.timer = Timer.periodic(pollInterval, (_) => _poll(session));
    _sessions.add(session);
  }

  Future<bool> _launchWithApp(String filePath, String appPath) {
    if (Platform.isMacOS) {
      return Process.run('open', ['-a', appPath, filePath])
          .then((r) => r.exitCode == 0);
    }
    if (Platform.isWindows) {
      return Process.run(appPath, [filePath], runInShell: true)
          .then((r) => r.exitCode == 0);
    }
    // Linux and fallback
    return Process.run(appPath, [filePath]).then((r) => r.exitCode == 0);
  }
```

7. Add `import 'dart:io';` if not already present (it is — `dart:io` is already imported).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/external_edit_service_test.dart`
Expected: PASS (6 tests — 5 existing + 1 new)

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/external_edit_service.dart app/test/services/external_edit_service_test.dart
git commit -m "feat(sftp): ExternalEditService.openExternalWith for app-specific launch"
```

---

### Task 6: `CodeEditorScreen` read-only mode

**Files:**
- Modify: `app/lib/widgets/code_editor_screen.dart`
- Modify: `app/assets/monaco_editor.html`
- Modify: `app/test/widgets/code_editor_screen_fallback_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `app/test/widgets/code_editor_screen_fallback_test.dart`, at the end of `main()`:

```dart
  testWidgets('readOnly mode: no save button, TextField is read-only', (tester) async {
    final service = FakeTransferService(utf8.encode('read only content'));
    await tester.pumpWidget(MaterialApp(
      home: Provider<SftpTransferService>.value(
        value: service,
        child: const CodeEditorScreen(
          host: Host(label: 't', host: 'h', username: 'u'),
          entry: SftpEntry(
            name: 'log.txt',
            path: '/var/log/log.txt',
            isDirectory: false,
            size: 17,
            modifiedAt: null,
          ),
          readOnly: true,
        ),
      ),
    ));
    await _pumpUntilFound(tester, find.byType(TextField));

    // No save button
    expect(find.byIcon(Icons.save_outlined), findsNothing);
    // Lock icon present
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    // TextField is read-only
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.readOnly, isTrue);
  });
```

Fix the `SftpEntry` constructor — `modifiedAt` is required so use `DateTime(2026)` (same as other tests):
```dart
          entry: SftpEntry(
            name: 'log.txt',
            path: '/var/log/log.txt',
            isDirectory: false,
            size: 17,
            modifiedAt: DateTime(2026),
          ),
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && flutter test test/widgets/code_editor_screen_fallback_test.dart`
Expected: FAIL — `No named parameter 'readOnly'`

- [ ] **Step 3: Add `setReadOnly` to Monaco HTML**

In `app/assets/monaco_editor.html`, add the following after the `window.getContent` function (around line 68):

```js
      window.setReadOnly = function(readonly) {
        editor.updateOptions({ readOnly: readonly });
      };
```

- [ ] **Step 4: Update `CodeEditorScreen`**

1. Add `readOnly` to the widget:
```dart
class CodeEditorScreen extends StatefulWidget {
  final Host host;
  final SftpEntry entry;
  final bool readOnly;

  const CodeEditorScreen({
    super.key,
    required this.host,
    required this.entry,
    this.readOnly = false,
  });
```

2. In `_loadFile`, after `_pushContentToEditor()` call on the webview path, add:
```dart
      if (_useWebView) {
        if (_ready) {
          _pushContentToEditor();
          if (widget.readOnly) {
            _controller!.runJavaScript('setReadOnly(true)');
          }
        }
      } else {
        _textController.text = _content!;
        setState(() => _ready = true);
      }
```

Also in `_onJsMessage`, in the `'ready'` branch, after `_pushContentToEditor()`:
```dart
    if (type == 'ready') {
      setState(() => _ready = true);
      if (_content != null) {
        _pushContentToEditor();
        if (widget.readOnly) {
          _controller!.runJavaScript('setReadOnly(true)');
        }
      }
```

3. In `build`, update AppBar actions and PopScope:
```dart
    return PopScope(
      canPop: widget.readOnly || !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showDiscardDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141414),
          title: Text(widget.entry.name,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
          actions: [
            if (widget.readOnly)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.lock_outline, size: 16, color: Color(0xFF888888)),
              )
            else ...[
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF22C55E)),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.save_outlined, size: 18),
                tooltip: 'Save (Ctrl+S)',
                onPressed: _saving ? null : _saveCurrent,
              ),
            ],
          ],
        ),
        body: !_ready
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
            : _useWebView
                ? WebViewWidget(controller: _controller!)
                : _buildFallbackEditor(),
      ),
    );
```

4. In `_buildFallbackEditor`, when `widget.readOnly` is true omit the `CallbackShortcuts` and set `readOnly: true` on TextField:
```dart
  Widget _buildFallbackEditor() {
    final field = TextField(
      controller: _textController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      autofocus: !widget.readOnly,
      readOnly: widget.readOnly,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: Color(0xFFD4D4D4),
        height: 1.5,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(12),
      ),
      onChanged: widget.readOnly ? null : (_) {
        if (!_isDirty) setState(() => _isDirty = true);
      },
    );
    if (widget.readOnly) return field;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveCurrent,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveCurrent,
      },
      child: field,
    );
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/code_editor_screen_fallback_test.dart`
Expected: PASS (5 tests — 4 existing + 1 new)

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/code_editor_screen.dart app/assets/monaco_editor.html \
        app/test/widgets/code_editor_screen_fallback_test.dart
git commit -m "feat(sftp): CodeEditorScreen readOnly mode with lock icon"
```

---

### Task 7: Context menu + submenu UI

**Files:**
- Modify: `app/lib/widgets/sftp_entry_context_menu.dart`
- Modify: `app/test/widgets/sftp_entry_context_menu_test.dart`

The "Open with ▶" submenu is implemented by listening on `onSecondaryTapUp` position (already available) and calling `showMenu` a second time. The menu widget itself passes the tap position through an `onOpenWith` callback that includes the `Offset` for positioning the submenu.

- [ ] **Step 1: Write failing tests**

Replace `app/test/widgets/sftp_entry_context_menu_test.dart`:

```dart
// app/test/widgets/sftp_entry_context_menu_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/widgets/sftp_entry_context_menu.dart';

final _file = SftpEntry(
  name: 'notes.txt',
  path: '/home/u/notes.txt',
  isDirectory: false,
  size: 10,
  modifiedAt: DateTime(2026),
);

void main() {
  testWidgets('context menu shows View and Edit for files', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SftpEntryContextMenu(
          entry: _file,
          onView: () {},
          onEdit: () {},
          onOpenWith: (_) {},
          onRename: () {},
          onDelete: () {},
          child: const Text('notes.txt'),
        ),
      ),
    ));

    await tester.tap(find.text('notes.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('View'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('context menu shows "Open with" for files', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SftpEntryContextMenu(
          entry: _file,
          onView: () {},
          onEdit: () {},
          onOpenWith: (_) {},
          onRename: () {},
          onDelete: () {},
          child: const Text('notes.txt'),
        ),
      ),
    ));

    await tester.tap(find.text('notes.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Open with'), findsOneWidget);
  });

  testWidgets('tapping View calls onView', (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SftpEntryContextMenu(
          entry: _file,
          onView: () => called = true,
          onEdit: () {},
          onOpenWith: (_) {},
          onRename: () {},
          onDelete: () {},
          child: const Text('notes.txt'),
        ),
      ),
    ));

    await tester.tap(find.text('notes.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
  });

  testWidgets('tapping "Open with" calls onOpenWith with an Offset', (tester) async {
    Offset? receivedOffset;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SftpEntryContextMenu(
          entry: _file,
          onView: () {},
          onEdit: () {},
          onOpenWith: (offset) => receivedOffset = offset,
          onRename: () {},
          onDelete: () {},
          child: const Text('notes.txt'),
        ),
      ),
    ));

    await tester.tap(find.text('notes.txt'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();

    expect(receivedOffset, isNotNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd app && flutter test test/widgets/sftp_entry_context_menu_test.dart`
Expected: FAIL — `No named parameter with the name 'onView'` and `onOpenWith`

- [ ] **Step 3: Rewrite `sftp_entry_context_menu.dart`**

```dart
// app/lib/widgets/sftp_entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/sftp_entry.dart';

class SftpEntryContextMenu extends StatelessWidget {
  final SftpEntry entry;
  final Widget child;
  // Directories use onOpen (Enter); files use the split callbacks below.
  final VoidCallback onOpen;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  // Called with the global tap position so the caller can position the submenu.
  final void Function(Offset position)? onOpenWith;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const SftpEntryContextMenu({
    super.key,
    required this.entry,
    required this.child,
    required this.onOpen,
    this.onView,
    this.onEdit,
    this.onOpenWith,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }

  void _show(BuildContext context, Offset pos) {
    final size = MediaQuery.of(context).size;
    final rect = RelativeRect.fromLTRB(
        pos.dx, pos.dy, size.width - pos.dx, size.height - pos.dy);
    showMenu<_Action>(
      context: context,
      position: rect,
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      items: [
        PopupMenuItem(
          value: _Action.open,
          height: 34,
          child: _Item(
            icon: entry.isDirectory ? Icons.folder_open : Icons.visibility_outlined,
            label: entry.isDirectory ? 'Enter' : 'View',
          ),
        ),
        if (!entry.isDirectory && onEdit != null)
          const PopupMenuItem(
              value: _Action.edit,
              height: 34,
              child: _Item(icon: Icons.edit_outlined, label: 'Edit')),
        if (!entry.isDirectory && onOpenWith != null)
          PopupMenuItem(
            value: _Action.openWith,
            height: 34,
            child: Row(children: const [
              Icon(Icons.apps, size: 14, color: Color(0xFFD4D4D4)),
              SizedBox(width: 8),
              Flexible(
                child: Text('Open with',
                    style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              Spacer(),
              Icon(Icons.chevron_right, size: 14, color: Color(0xFF555555)),
            ]),
          ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
            value: _Action.rename,
            height: 34,
            child: _Item(icon: Icons.drive_file_rename_outline, label: 'Rename')),
        const PopupMenuItem(
            value: _Action.delete,
            height: 34,
            child: _Item(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: Color(0xFFEF4444))),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
            value: _Action.copyPath,
            height: 34,
            child: _Item(icon: Icons.content_copy, label: 'Copy path')),
      ],
    ).then((a) {
      if (a == null) return;
      switch (a) {
        case _Action.open:
          entry.isDirectory ? onOpen() : onView?.call();
        case _Action.edit:
          onEdit?.call();
        case _Action.openWith:
          onOpenWith?.call(pos);
        case _Action.rename:
          onRename();
        case _Action.delete:
          onDelete();
        case _Action.copyPath:
          Clipboard.setData(ClipboardData(text: entry.path));
      }
    });
  }
}

enum _Action { open, edit, openWith, rename, delete, copyPath }

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Item(
      {required this.icon,
      required this.label,
      this.color = const Color(0xFFD4D4D4)});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Flexible(
        child: Text(label,
            style: TextStyle(color: color, fontSize: 13),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/sftp_entry_context_menu_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/sftp_entry_context_menu.dart \
        app/test/widgets/sftp_entry_context_menu_test.dart
git commit -m "feat(sftp): context menu View + Edit + Open-with submenu trigger"
```

---

### Task 8: Wire `sftp_panel.dart` — View, Edit, submenu

**Files:**
- Modify: `app/lib/widgets/sftp_panel.dart`
- Modify: `app/lib/widgets/dual_panel_sftp_screen.dart`

No new test file — wiring is covered by the full test run and `flutter analyze`.

- [ ] **Step 1: Add imports to `sftp_panel.dart`**

Add to the import block:
```dart
import '../models/app_option.dart';
import '../services/app_discovery_service.dart';
import 'package:file_selector/file_selector.dart';
```

- [ ] **Step 2: Add `_openViewer` and update `_openEditor`**

Add `_openViewer` right after `_onEntryTap`:
```dart
  Future<void> _openViewer(SftpEntry entry) {
    final service = context.read<SftpTransferService>();
    final externalEdit = context.read<ExternalEditService>();
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            Provider<SftpTransferService>.value(value: service),
            Provider<ExternalEditService>.value(value: externalEdit),
          ],
          child: CodeEditorScreen(
              host: widget.host!, entry: entry, readOnly: true),
        ),
      ),
    );
  }
```

- [ ] **Step 3: Add `_showOpenWithSubmenu`**

Add after `_openExternal`:
```dart
  Future<void> _showOpenWithSubmenu(SftpEntry entry, Offset pos) async {
    final discovery = context.read<AppDiscoveryService>();
    final externalService = context.read<ExternalEditService>();
    final messenger = ScaffoldMessenger.of(context);

    // Use a stub local path with just the extension for fast MIME lookup —
    // avoids a full download before the submenu is even shown.
    final stubPath = '/tmp/stub${entry.extension.isEmpty ? '' : '.${entry.extension}'}';
    final apps = await discovery.getAppsFor(stubPath);

    if (!mounted) return;
    final size = MediaQuery.of(context).size;

    final selected = await showMenu<_OpenWithChoice>(
      context: context,
      position: RelativeRect.fromLTRB(
          pos.dx, pos.dy, size.width - pos.dx, size.height - pos.dy),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      items: [
        for (final app in apps)
          PopupMenuItem(
            value: _OpenWithChoice(app: app),
            height: 34,
            child: Row(children: [
              const Icon(Icons.apps, size: 14, color: Color(0xFF888888)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(app.name,
                    style: const TextStyle(
                        color: Color(0xFFD4D4D4), fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              if (app.isDefault) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('default',
                      style: TextStyle(
                          color: Color(0xFF22C55E),
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ),
        if (apps.isNotEmpty) const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: _OpenWithChoice(choose: true),
          height: 34,
          child: Row(children: [
            Icon(Icons.folder_open_outlined, size: 14, color: Color(0xFFD4D4D4)),
            SizedBox(width: 8),
            Text('Choose…',
                style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 13)),
          ]),
        ),
      ],
    );

    if (selected == null || !mounted) return;

    String? appPath = selected.app?.executablePath;
    if (selected.choose) {
      appPath = await _pickApp();
    }
    if (appPath == null) return;

    _openWithApp(entry, appPath, externalService, messenger);
  }

  /// Shows an OS file picker for choosing an application executable.
  Future<String?> _pickApp() async {
    if (Platform.isMacOS) {
      const typeGroup = XTypeGroup(label: 'Applications', extensions: ['app']);
      final file = await openFile(
          acceptedTypeGroups: [typeGroup],
          initialDirectory: '/Applications');
      return file?.path;
    }
    if (Platform.isWindows) {
      const typeGroup = XTypeGroup(label: 'Executables', extensions: ['exe']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      return file?.path;
    }
    // Linux: any file (executables have no fixed extension)
    final file = await openFile();
    return file?.path;
  }

  void _openWithApp(SftpEntry entry, String appPath,
      ExternalEditService externalService, ScaffoldMessengerState messenger) {
    externalService.onUploaded = (name) => messenger.showSnackBar(SnackBar(
        content: Text('Uploaded $name to server'),
        duration: const Duration(seconds: 2)));
    externalService.onUploadError = (name, e) => messenger.showSnackBar(SnackBar(
        content: Text('Upload of $name failed: $e'),
        backgroundColor: const Color(0xFF2A1A1A)));
    externalService
        .openExternalWith(widget.host!, entry, appPath)
        .then((_) {
      messenger.showSnackBar(SnackBar(
          content: Text('Opened ${entry.name} — watching for changes'),
          duration: const Duration(seconds: 2)));
    }).catchError((e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Open with failed: $e'),
          backgroundColor: const Color(0xFF2A1A1A)));
    });
  }
```

Add the helper class at file scope (outside the State class, at the bottom of the file):
```dart
class _OpenWithChoice {
  const _OpenWithChoice({this.app, this.choose = false});
  final AppOption? app;
  final bool choose;
}
```

- [ ] **Step 4: Update `_buildEntryTile` callback wiring**

Replace the `SftpEntryContextMenu` call in `_buildEntryTile`:
```dart
    return SftpEntryContextMenu(
      entry: entry,
      onOpen: () => _onEntryTap(entry),
      onView: entry.isDirectory ? null : () => _openViewer(entry),
      onEdit: entry.isDirectory ? null : () => _openEditor(entry),
      onOpenWith: entry.isDirectory
          ? null
          : (pos) => _showOpenWithSubmenu(entry, pos),
      onRename: () => _showRenameDialog(prov, entry),
      onDelete: () => _showDeleteConfirm(prov, [entry]),
```

Also remove the now-unused `onOpen` in `SftpEntryContextMenu` since "Enter" for directories goes through `onOpen` and "View" for files goes through `onView`. The widget's `onOpen` callback maps to directory navigation — keep it. Update the call:
```dart
      onOpen: () => _onEntryTap(entry),   // directory Enter (unchanged)
```

- [ ] **Step 5: Register `AppDiscoveryService` in `dual_panel_sftp_screen.dart`**

Add import:
```dart
import '../services/app_discovery_service.dart';
```

In the `MultiProvider` providers list (after `ExternalEditService`):
```dart
        Provider(
          create: (_) => AppDiscoveryService(),
          dispose: (_, AppDiscoveryService s) => s.dispose(),
        ),
```

Also add the same registration to `SftpPanel`'s caller in `sftp_panel.dart` (the panel itself reads from context, so the provider must be above it in the tree). Check if `SftpPanel` is always under `dual_panel_sftp_screen.dart`'s MultiProvider — it is via `DualPanelSftpScreen`. For the standalone `SftpPanel` path (used in `MainScreen`), register in `MainScreen` or wherever `SftpPanel` is mounted — search:

```bash
grep -rn "SftpPanel(" app/lib --include="*.dart" | grep -v dual_panel
```

Register `AppDiscoveryService` in each call site found.

- [ ] **Step 6: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart app/lib/widgets/dual_panel_sftp_screen.dart
git commit -m "feat(sftp): wire View/Edit/Open-with in SFTP panel + AppDiscoveryService"
```

---

### Task 9: Full test run + changelog + docs

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Run the full test suite and analyzer**

Run: `cd app && flutter analyze && flutter test`
Expected: analyzer clean, all tests pass.

- [ ] **Step 2: Update `CHANGELOG.md` under `[Unreleased]`**

Add under `### Added`:
```markdown
- **SFTP View mode** — right-clicking (or double-clicking) a file in the SFTP panel now shows separate **View** (read-only preview, lock icon in the AppBar, no save) and **Edit** (existing editable mode) actions so you can open log files and config files without risking accidental edits.
- **Open with… (SFTP)** — replaces "Open with external app" with a **Open with ▶** submenu that lists every application installed on your machine that can open the file's type (macOS via `NSWorkspace`, Linux via XDG MIME + `.desktop` files, Windows via registry). A **Choose…** option lets you pick any application with the OS file picker. The selected app is launched with the downloaded file and yourssh watches for saves and uploads changes back automatically.
```

- [ ] **Step 3: Update `CLAUDE.md` services list**

Add after the `ExternalEditService` bullet:
```markdown
- `AppDiscoveryService` — discovers installed applications for a given file path, filtered by MIME type; per-extension cache; macOS uses `NSWorkspace` via a `yourssh/app_discovery` Flutter method channel (`AppDelegate.swift`), Linux parses XDG `.desktop` files in Dart, Windows uses PowerShell registry queries
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md CLAUDE.md
git commit -m "docs: changelog + service docs for SFTP View + Open with"
```

---

## Self-Review Notes

**Spec coverage:**
- View (read-only) ✅ Task 6
- Edit stays as-is ✅ Task 8 wiring
- "Open with ▶" submenu ✅ Task 7 (context menu) + Task 8 (submenu logic)
- macOS NSWorkspace channel ✅ Task 3
- Linux .desktop parsing ✅ Task 2
- Windows PowerShell ✅ Task 2 (in `_queryWindows`)
- "Choose…" file picker ✅ Task 8 (`_pickApp`)
- `ExternalEditService.openExternalWith` ✅ Task 5
- `file_selector` dep ✅ Task 4
- AppOption model ✅ Task 1
- Per-extension cache ✅ Task 2 (`AppDiscoveryService.withQuerier` test)
- Error → returns [] ✅ Task 2 test + implementation
- Testing ✅ Tasks 1, 2, 5, 6, 7

**Type consistency:**
- `AppOption` defined Task 1, used in Task 2, 7, 8 ✅
- `AppDiscoveryService.getAppsFor(String)` → `Future<List<AppOption>>` consistent throughout ✅
- `ExternalEditService.openExternalWith(Host, SftpEntry, String)` defined Task 5, called Task 8 ✅
- `onOpenWith: void Function(Offset)` defined Task 7, called Task 8 ✅
- `_OpenWithChoice` defined and used in Task 8 ✅
