# Local Shell Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users pick which shell the local terminal runs (Git Bash, WSL, pwsh, cmd on Windows; any `/etc/shells` entry on macOS/Linux; custom executables anywhere), via a Settings default + a per-session picker on the new-tab menu.

**Architecture:** New `ShellProfile` model + pure-parsing `shell_detection.dart` service (pattern: `os_detection.dart`). `SettingsProvider` persists `defaultShellId` + custom profiles; detected profiles re-detected each launch (stable ids). `LocalShellService.openShell({profile})` spawns the chosen executable+args; `SessionProvider.newLocalSession` resolves the default via a callback wired in `main.dart`. Spec: `docs/superpowers/specs/2026-06-06-local-shell-picker-design.md`.

**Tech Stack:** Flutter/Dart, flutter_pty (local fork, supports `arguments`), shared_preferences, file_selector, package:path.

---

## File map

| File | Action | Responsibility |
|---|---|---|
| `app/lib/models/shell_profile.dart` | Create | `ShellProfile` model, JSON, `resolveShellProfile()` |
| `app/lib/services/shell_detection.dart` | Create | UTF-16LE/wsl/etc-shells parsers + `detectShells()` |
| `app/lib/models/local_session.dart` | Modify | `profile` field, profile-aware `tabLabel` |
| `app/lib/services/local_shell_service.dart` | Modify | `PtyFactory` gains args; `openShell({profile})` |
| `app/lib/providers/settings_provider.dart` | Modify | `defaultShellId`, custom/detected profiles, persistence |
| `app/lib/providers/session_provider.dart` | Modify | `newLocalSession({profile, platformDefault})`, resolver callback, dangling warning |
| `app/lib/main.dart` | Modify | run detection at startup, wire resolver |
| `app/lib/widgets/settings_screen.dart` | Modify | "Default local shell" dropdown + custom-shell rows/dialog |
| `app/lib/screens/main_screen.dart` | Modify | `_AddTabBtn` shell menu, callback signature threading |
| `app/test/models/shell_profile_test.dart` | Create | JSON round-trip, resolution |
| `app/test/services/shell_detection_test.dart` | Create | parsers + detection branches |
| `app/test/services/local_shell_service_test.dart` | Modify | factory signature, profile spawn/restart/tabLabel |
| `app/test/providers/settings_provider_shell_test.dart` | Create | persistence, default reset |
| `app/test/providers/session_provider_local_test.dart` | Modify | factory signature, resolver/dangling tests |

---

### Task 1: `ShellProfile` model + `resolveShellProfile`

**Files:**
- Create: `app/lib/models/shell_profile.dart`
- Test: `app/test/models/shell_profile_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/shell_profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/shell_profile.dart';

void main() {
  group('ShellProfile JSON', () {
    test('round-trips all fields', () {
      const profile = ShellProfile(
        id: 'custom-abc',
        name: 'Nushell',
        executable: '/usr/local/bin/nu',
        args: ['-l', '--config', 'x'],
        isCustom: true,
      );
      final back = ShellProfile.fromJson(profile.toJson());
      expect(back.id, 'custom-abc');
      expect(back.name, 'Nushell');
      expect(back.executable, '/usr/local/bin/nu');
      expect(back.args, ['-l', '--config', 'x']);
      expect(back.isCustom, true);
    });

    test('fromJson defaults args/isCustom when missing', () {
      final p = ShellProfile.fromJson({
        'id': 'cmd', 'name': 'Command Prompt', 'executable': 'cmd.exe',
      });
      expect(p.args, isEmpty);
      expect(p.isCustom, false);
    });
  });

  group('resolveShellProfile', () {
    const gitBash = ShellProfile(
        id: 'git-bash', name: 'Git Bash', executable: 'bash.exe');

    test('null id means platform default, not dangling', () {
      final r = resolveShellProfile([gitBash], null);
      expect(r.profile, isNull);
      expect(r.dangling, false);
    });

    test('matching id returns the profile', () {
      final r = resolveShellProfile([gitBash], 'git-bash');
      expect(r.profile, same(gitBash));
      expect(r.dangling, false);
    });

    test('dangling id falls back to null profile and flags it', () {
      final r = resolveShellProfile([gitBash], 'wsl-Ubuntu');
      expect(r.profile, isNull);
      expect(r.dangling, true);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/shell_profile_test.dart`
Expected: FAIL — `shell_profile.dart` does not exist.

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/models/shell_profile.dart
//
// One launchable local shell: detected (PowerShell, Git Bash, a WSL distro,
// an /etc/shells entry) or user-added custom. Detected profiles are
// re-detected every launch and never persisted; their ids are stable so the
// saved defaultShellId keeps pointing at them. Only custom profiles
// serialize to prefs.

class ShellProfile {
  final String id;
  final String name;
  final String executable;
  final List<String> args;
  final bool isCustom;

  const ShellProfile({
    required this.id,
    required this.name,
    required this.executable,
    this.args = const [],
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'executable': executable,
        'args': args,
        'isCustom': isCustom,
      };

  factory ShellProfile.fromJson(Map<String, dynamic> json) => ShellProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        executable: json['executable'] as String,
        args: (json['args'] as List<dynamic>? ?? const [])
            .map((a) => a as String)
            .toList(),
        isCustom: json['isCustom'] as bool? ?? false,
      );
}

/// Result of resolving the configured default shell. [dangling] is true when
/// a non-null defaultShellId no longer matches any profile (the shell was
/// uninstalled) — callers fall back to the platform default and surface a
/// warning instead of erroring.
typedef ShellResolution = ({ShellProfile? profile, bool dangling});

ShellResolution resolveShellProfile(
  List<ShellProfile> profiles,
  String? defaultShellId,
) {
  if (defaultShellId == null) return (profile: null, dangling: false);
  for (final p in profiles) {
    if (p.id == defaultShellId) return (profile: p, dangling: false);
  }
  return (profile: null, dangling: true);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/shell_profile_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/shell_profile.dart app/test/models/shell_profile_test.dart
git commit -m "feat: ShellProfile model with default-shell resolution"
```

---

### Task 2: Shell detection service

**Files:**
- Create: `app/lib/services/shell_detection.dart`
- Test: `app/test/services/shell_detection_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/services/shell_detection_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/shell_detection.dart';

/// Encodes a string as UTF-16LE bytes — what wsl.exe emits on stdout.
List<int> utf16le(String s) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    out..add(u & 0xff)..add(u >> 8);
  }
  return out;
}

void main() {
  group('parseWslDistroList', () {
    test('decodes UTF-16LE with CRLF line ends, drops blanks', () {
      expect(parseWslDistroList(utf16le('Ubuntu\r\nDebian\r\n\r\n')),
          ['Ubuntu', 'Debian']);
    });

    test('strips a leading BOM', () {
      expect(parseWslDistroList([0xFF, 0xFE, ...utf16le('Ubuntu\r\n')]),
          ['Ubuntu']);
    });

    test('empty output yields no distros', () {
      expect(parseWslDistroList([]), isEmpty);
    });
  });

  group('parseEtcShells', () {
    test('drops comments, blanks and duplicates', () {
      expect(
        parseEtcShells('# /etc/shells\n/bin/bash\n\n/bin/zsh\n/bin/bash\n'),
        ['/bin/bash', '/bin/zsh'],
      );
    });
  });

  group('detectShells windows', () {
    test('always offers powershell+cmd, adds pwsh/git-bash/wsl when found',
        () async {
      final profiles = await detectShells(
        isWindows: true,
        env: {'ProgramFiles': r'C:\Program Files', 'PATH': ''},
        fileExists: (path) =>
            path == r'C:\Program Files\PowerShell\7\pwsh.exe' ||
            path == r'C:\Program Files\Git\bin\bash.exe',
        runRaw: (exe, args) async => utf16le('Ubuntu\r\n'),
      );
      expect(profiles.map((s) => s.id).toList(),
          ['powershell', 'cmd', 'pwsh', 'git-bash', 'wsl-Ubuntu']);
      final wsl = profiles.last;
      expect(wsl.executable, 'wsl.exe');
      expect(wsl.args, ['-d', 'Ubuntu']);
    });

    test('pwsh found via PATH scan', () async {
      final profiles = await detectShells(
        isWindows: true,
        env: {'PATH': r'C:\tools;C:\pwsh'},
        fileExists: (path) => path == r'C:\pwsh\pwsh.exe',
        runRaw: (_, __) async => null,
      );
      expect(profiles.map((s) => s.id), contains('pwsh'));
      expect(profiles.firstWhere((s) => s.id == 'pwsh').executable,
          r'C:\pwsh\pwsh.exe');
    });

    test('wsl failure yields no wsl profiles, detection continues', () async {
      final profiles = await detectShells(
        isWindows: true,
        env: {},
        fileExists: (_) => false,
        runRaw: (_, __) async => null,
      );
      expect(profiles.map((s) => s.id).toList(), ['powershell', 'cmd']);
    });
  });

  group('detectShells unix', () {
    test(r'$SHELL first, /etc/shells entries filtered to existing', () async {
      final profiles = await detectShells(
        isWindows: false,
        env: {'SHELL': '/bin/zsh'},
        fileExists: (path) => path != '/bin/missing',
        readFile: (_) => '/bin/bash\n/bin/missing\n/bin/zsh\n',
      );
      expect(profiles.map((s) => s.executable).toList(),
          ['/bin/zsh', '/bin/bash']);
      expect(profiles.first.id, 'etc-/bin/zsh');
      expect(profiles.first.name, 'zsh');
    });

    test(r'unreadable /etc/shells leaves only $SHELL', () async {
      final profiles = await detectShells(
        isWindows: false,
        env: {'SHELL': '/bin/zsh'},
        fileExists: (_) => true,
        readFile: (_) => null,
      );
      expect(profiles.map((s) => s.executable).toList(), ['/bin/zsh']);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/shell_detection_test.dart`
Expected: FAIL — `shell_detection.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Note: use `p.windows.join` in the Windows branch and `p.posix.basename` in the unix branch so behavior (and tests) are identical on every host OS.

```dart
// app/lib/services/shell_detection.dart
//
// Detects shells installed on this machine for the local-terminal picker.
// Pattern follows os_detection.dart: parsing is pure (unit-testable), IO is
// injected via callbacks so tests never touch the filesystem or spawn
// processes. Detection must never block opening a terminal: every failure
// degrades to a partial or empty list.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/shell_profile.dart';

/// Decodes UTF-16LE bytes (wsl.exe's stdout encoding), dropping a BOM.
String decodeUtf16Le(List<int> bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(bytes[i] | (bytes[i + 1] << 8));
  }
  if (units.isNotEmpty && units.first == 0xFEFF) units.removeAt(0);
  return String.fromCharCodes(units);
}

/// Parses `wsl.exe --list --quiet` output into distro names.
List<String> parseWslDistroList(List<int> bytes) {
  return decodeUtf16Le(bytes)
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Parses /etc/shells: comments and blanks dropped, first occurrence wins.
List<String> parseEtcShells(String content) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (seen.add(line)) out.add(line);
  }
  return out;
}

typedef FileExists = bool Function(String path);
typedef ReadFile = String? Function(String path);
typedef RunRaw = Future<List<int>?> Function(String exe, List<String> args);

bool _defaultFileExists(String path) => File(path).existsSync();

String? _defaultReadFile(String path) {
  try {
    return File(path).readAsStringSync();
  } catch (_) {
    return null;
  }
}

/// Runs a process and returns raw stdout bytes, or null on any failure
/// (missing binary, non-zero exit) — callers treat null as "feature absent".
Future<List<int>?> _defaultRunRaw(String exe, List<String> args) async {
  try {
    final result = await Process.run(exe, args, stdoutEncoding: null);
    if (result.exitCode != 0) return null;
    return result.stdout as List<int>;
  } catch (_) {
    return null;
  }
}

Future<List<ShellProfile>> detectShells({
  bool? isWindows,
  Map<String, String>? env,
  FileExists? fileExists,
  ReadFile? readFile,
  RunRaw? runRaw,
}) async {
  final windows = isWindows ?? Platform.isWindows;
  final e = env ?? Platform.environment;
  final exists = fileExists ?? _defaultFileExists;
  try {
    return windows
        ? await _detectWindows(e, exists, runRaw ?? _defaultRunRaw)
        : _detectUnix(e, exists, readFile ?? _defaultReadFile);
  } catch (_) {
    return const [];
  }
}

Future<List<ShellProfile>> _detectWindows(
  Map<String, String> env,
  FileExists exists,
  RunRaw run,
) async {
  final profiles = <ShellProfile>[
    const ShellProfile(
        id: 'powershell', name: 'PowerShell', executable: 'powershell.exe'),
    const ShellProfile(
        id: 'cmd', name: 'Command Prompt', executable: 'cmd.exe'),
  ];

  // PowerShell 7: PATH scan first, then the default install dir.
  String? pwsh;
  for (final dir in (env['PATH'] ?? '').split(';')) {
    if (dir.isEmpty) continue;
    final candidate = p.windows.join(dir, 'pwsh.exe');
    if (exists(candidate)) {
      pwsh = candidate;
      break;
    }
  }
  final programFiles = env['ProgramFiles'];
  if (pwsh == null && programFiles != null) {
    final candidate = p.windows.join(programFiles, 'PowerShell', '7', 'pwsh.exe');
    if (exists(candidate)) pwsh = candidate;
  }
  if (pwsh != null) {
    profiles.add(ShellProfile(id: 'pwsh', name: 'PowerShell 7', executable: pwsh));
  }

  // Git Bash: first hit of the usual install locations.
  final localAppData = env['LOCALAPPDATA'];
  for (final base in [
    programFiles,
    env['ProgramFiles(x86)'],
    if (localAppData != null) p.windows.join(localAppData, 'Programs'),
  ]) {
    if (base == null) continue;
    final candidate = p.windows.join(base, 'Git', 'bin', 'bash.exe');
    if (exists(candidate)) {
      profiles.add(ShellProfile(
          id: 'git-bash', name: 'Git Bash', executable: candidate));
      break;
    }
  }

  // WSL: one profile per distro. Any wsl.exe failure → no WSL profiles.
  final raw = await run('wsl.exe', ['--list', '--quiet']);
  if (raw != null) {
    for (final distro in parseWslDistroList(raw)) {
      profiles.add(ShellProfile(
        id: 'wsl-$distro',
        name: 'WSL · $distro',
        executable: 'wsl.exe',
        args: ['-d', distro],
      ));
    }
  }
  return profiles;
}

List<ShellProfile> _detectUnix(
  Map<String, String> env,
  FileExists exists,
  ReadFile read,
) {
  // $SHELL always first; /etc/shells fills in the rest.
  final paths = <String>[];
  final userShell = env['SHELL'];
  if (userShell != null && userShell.isNotEmpty) paths.add(userShell);
  final etc = read('/etc/shells');
  if (etc != null) {
    for (final path in parseEtcShells(etc)) {
      if (!paths.contains(path)) paths.add(path);
    }
  }
  return [
    for (final path in paths)
      if (exists(path))
        ShellProfile(
            id: 'etc-$path', name: p.posix.basename(path), executable: path),
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/shell_detection_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/shell_detection.dart app/test/services/shell_detection_test.dart
git commit -m "feat: shell detection service (wsl/git-bash/pwsh, /etc/shells)"
```

---

### Task 3: `LocalShellService` + `LocalSession` profile support

**Files:**
- Modify: `app/lib/models/local_session.dart`
- Modify: `app/lib/services/local_shell_service.dart`
- Test: `app/test/services/local_shell_service_test.dart`
- Modify (signature only): every `ptyFactory:` lambda under `app/test/` — find them with `grep -rn "ptyFactory:" app/test`

- [ ] **Step 1: Write the failing tests**

Append a new group to `app/test/services/local_shell_service_test.dart` and add the import `import 'package:yourssh/models/shell_profile.dart';`:

```dart
  group('shell profiles', () {
    test('openShell passes profile executable and args to the factory',
        () async {
      String? gotShell;
      List<String>? gotArgs;
      final svc = LocalShellService(
        ptyFactory: (shell, args, c, r, env) {
          gotShell = shell;
          gotArgs = args;
          return fakePty;
        },
      );
      const profile = ShellProfile(
        id: 'wsl-Ubuntu',
        name: 'WSL · Ubuntu',
        executable: 'wsl.exe',
        args: ['-d', 'Ubuntu'],
      );
      final session = await svc.openShell(profile: profile);
      expect(gotShell, 'wsl.exe');
      expect(gotArgs, ['-d', 'Ubuntu']);
      expect(session.profile, same(profile));
    });

    test('restartShell reuses the session profile', () async {
      final shells = <String>[];
      final svc = LocalShellService(
        ptyFactory: (shell, args, c, r, env) {
          shells.add(shell);
          return FakePtyRunner();
        },
      );
      const profile = ShellProfile(
          id: 'git-bash', name: 'Git Bash', executable: r'C:\Git\bin\bash.exe');
      final session = await svc.openShell(profile: profile);
      session.status = LocalSessionStatus.exited;
      await svc.restartShell(session);
      expect(shells, [r'C:\Git\bin\bash.exe', r'C:\Git\bin\bash.exe']);
    });

    test('openShell without profile falls back to resolveShell', () async {
      String? gotShell;
      List<String>? gotArgs;
      final svc = LocalShellService(
        ptyFactory: (shell, args, c, r, env) {
          gotShell = shell;
          gotArgs = args;
          return fakePty;
        },
      );
      await svc.openShell();
      expect(
        gotShell,
        LocalShellService.resolveShell(Platform.environment,
            isWindows: Platform.isWindows),
      );
      expect(gotArgs, isEmpty);
    });

    test('tabLabel uses the profile name when a profile was chosen', () async {
      final session = await service.openShell(
          profile: const ShellProfile(
              id: 'git-bash', name: 'Git Bash', executable: 'bash.exe'));
      expect(session.tabLabel, matches(RegExp(r'^Git Bash \d+$')));
    });

    test('tabLabel stays "Local N" without a profile', () async {
      final session = await service.openShell();
      expect(session.tabLabel, matches(RegExp(r'^Local \d+$')));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/local_shell_service_test.dart`
Expected: COMPILE FAIL — factory lambdas have the wrong arity / `openShell` takes no `profile`.

- [ ] **Step 3: Implement**

`app/lib/models/local_session.dart` — add import + field + label:

```dart
import 'shell_profile.dart';
```

```dart
  /// Shell this session was opened with; null = platform default. Kept so
  /// "Restart shell" relaunches the same shell.
  final ShellProfile? profile;

  LocalSession({
    required this.terminal,
    this.profile,
    this.status = LocalSessionStatus.running,
    this.customLabel,
    this.colorTag,
    this.isPinned = false,
  })  : id = const Uuid().v4(),
        _labelIndex = ++_labelCounter;

  @override
  String get tabLabel => customLabel ?? '${profile?.name ?? 'Local'} $_labelIndex';
```

`app/lib/services/local_shell_service.dart` — add import `'../models/shell_profile.dart'`; change typedef, default factory, `openShell`, `_spawnPty`:

```dart
typedef PtyFactory = PtyRunner Function(
  String shell,
  List<String> args,
  int columns,
  int rows,
  Map<String, String> environment,
);
```

```dart
  static PtyRunner _defaultFactory(
    String shell,
    List<String> args,
    int columns,
    int rows,
    Map<String, String> environment,
  ) =>
      FlutterPtyRunner(
        Pty.start(shell,
            arguments: args,
            columns: columns,
            rows: rows,
            environment: environment),
      );
```

```dart
  Future<LocalSession> openShell({ShellProfile? profile}) async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal, profile: profile);
    _sessions[session.id] = session;
    _spawnPty(session);
    return session;
  }
```

In `_spawnPty`, replace the shell resolution and factory call:

```dart
    final profile = session.profile;
    final shell = profile?.executable ??
        resolveShell(Platform.environment, isWindows: Platform.isWindows);
    final args = profile?.args ?? const <String>[];

    try {
      final pty = _ptyFactory(
        shell,
        args,
        terminal.viewWidth,
        terminal.viewHeight,
        {...Platform.environment, 'TERM': 'xterm-256color'},
      );
```

Then fix every test factory lambda found by `grep -rn "ptyFactory:" app/test` to the 5-arg form, e.g. in `local_shell_service_test.dart`:

```dart
    service = LocalShellService(
      ptyFactory: (shell, args, cols, rows, env) => fakePty,
    );
```

and the throwing one:

```dart
      final badService = LocalShellService(
        ptyFactory: (_, _, _, _, _) => throw Exception('pty unavailable'),
      );
```

and in `app/test/providers/session_provider_local_test.dart`:

```dart
    p.localShell =
        LocalShellService(ptyFactory: (shell, args, c, r, env) => _FakePty());
```

```dart
      final shell = LocalShellService(ptyFactory: (s, a, c, r, env) => pty);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/local_shell_service_test.dart test/providers/session_provider_local_test.dart`
Expected: PASS (all existing + 5 new)

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/local_session.dart app/lib/services/local_shell_service.dart app/test
git commit -m "feat: LocalShellService spawns a chosen ShellProfile"
```

---

### Task 4: `SettingsProvider` shell persistence

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Test: `app/test/providers/settings_provider_shell_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/providers/settings_provider_shell_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/shell_profile.dart';
import 'package:yourssh/providers/settings_provider.dart';

/// SettingsProvider kicks off _load() in its constructor; give the async
/// prefs read a microtask turn before asserting.
Future<SettingsProvider> loadedProvider() async {
  final p = SettingsProvider();
  await Future<void>.delayed(Duration.zero);
  return p;
}

const _nu = ShellProfile(
  id: 'custom-1',
  name: 'Nu',
  executable: '/usr/bin/nu',
  args: ['-l'],
  isCustom: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('custom shell profiles persist across provider instances', () async {
    final p1 = await loadedProvider();
    await p1.addCustomShellProfile(_nu);
    final p2 = await loadedProvider();
    expect(p2.customShellProfiles, hasLength(1));
    expect(p2.customShellProfiles.first.name, 'Nu');
    expect(p2.customShellProfiles.first.args, ['-l']);
  });

  test('setDefaultShellId persists; null clears it', () async {
    final p1 = await loadedProvider();
    await p1.setDefaultShellId('git-bash');
    expect((await loadedProvider()).defaultShellId, 'git-bash');
    await p1.setDefaultShellId(null);
    expect((await loadedProvider()).defaultShellId, isNull);
  });

  test('removing the default custom shell resets defaultShellId', () async {
    final p = await loadedProvider();
    await p.addCustomShellProfile(_nu);
    await p.setDefaultShellId('custom-1');
    await p.removeCustomShellProfile('custom-1');
    expect(p.defaultShellId, isNull);
    expect((await loadedProvider()).defaultShellId, isNull);
  });

  test('resolveDefaultShell flags a dangling id', () async {
    final p = await loadedProvider();
    await p.setDefaultShellId('wsl-Gone');
    final r = p.resolveDefaultShell();
    expect(r.profile, isNull);
    expect(r.dangling, true);
  });

  test('allShellProfiles = detected + custom', () async {
    final p = await loadedProvider();
    p.setDetectedShells(const [
      ShellProfile(id: 'powershell', name: 'PowerShell', executable: 'powershell.exe'),
    ]);
    await p.addCustomShellProfile(_nu);
    expect(p.allShellProfiles.map((s) => s.id), ['powershell', 'custom-1']);
  });

  test('malformed customShellProfiles JSON keeps defaults', () async {
    SharedPreferences.setMockInitialValues({'customShellProfiles': 'not-json'});
    final p = await loadedProvider();
    expect(p.customShellProfiles, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/settings_provider_shell_test.dart`
Expected: COMPILE FAIL — fields/methods missing.

- [ ] **Step 3: Implement in `settings_provider.dart`**

Add import:

```dart
import '../models/shell_profile.dart';
```

Add fields after `dashboardSort`:

```dart
  /// Default shell id for new local terminals; null = platform default
  /// (today's resolveShell behavior).
  String? defaultShellId;

  /// User-added shells; the only profiles that persist.
  List<ShellProfile> customShellProfiles = [];

  /// Shells found on this machine; re-detected each launch by main.dart via
  /// setDetectedShells, never persisted (ids are stable across launches).
  List<ShellProfile> detectedShellProfiles = [];

  List<ShellProfile> get allShellProfiles =>
      [...detectedShellProfiles, ...customShellProfiles];
```

Add to `_load()` before `notifyListeners()`:

```dart
    defaultShellId = prefs.getString('defaultShellId');
    final shellsJson = prefs.getString('customShellProfiles');
    if (shellsJson != null) {
      try {
        customShellProfiles = (jsonDecode(shellsJson) as List<dynamic>)
            .map((j) => ShellProfile.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // Corrupted prefs: keep defaults rather than crash boot.
        debugPrint(
            '[SettingsProvider] customShellProfiles JSON malformed: $e');
      }
    }
```

Add methods after `save()`:

```dart
  void setDetectedShells(List<ShellProfile> shells) {
    detectedShellProfiles = shells;
    notifyListeners();
  }

  ShellResolution resolveDefaultShell() =>
      resolveShellProfile(allShellProfiles, defaultShellId);

  Future<void> setDefaultShellId(String? id) async {
    defaultShellId = id;
    await _persistShellSettings();
  }

  Future<void> addCustomShellProfile(ShellProfile profile) async {
    customShellProfiles = [...customShellProfiles, profile];
    await _persistShellSettings();
  }

  Future<void> removeCustomShellProfile(String id) async {
    customShellProfiles =
        customShellProfiles.where((s) => s.id != id).toList();
    if (defaultShellId == id) defaultShellId = null;
    await _persistShellSettings();
  }

  Future<void> _persistShellSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customShellProfiles',
        jsonEncode([for (final s in customShellProfiles) s.toJson()]));
    if (defaultShellId == null) {
      await prefs.remove('defaultShellId');
    } else {
      await prefs.setString('defaultShellId', defaultShellId!);
    }
    notifyListeners();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/settings_provider_shell_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/providers/settings_provider_shell_test.dart
git commit -m "feat: persist default shell + custom shell profiles in settings"
```

---

### Task 5: `SessionProvider.newLocalSession` profile routing

**Files:**
- Modify: `app/lib/providers/session_provider.dart` (`newLocalSession`, new callback field)
- Test: `app/test/providers/session_provider_local_test.dart`

- [ ] **Step 1: Write the failing tests**

Append to `session_provider_local_test.dart` (add import `package:yourssh/models/shell_profile.dart`):

```dart
  group('shell picker', () {
    const gitBash = ShellProfile(
        id: 'git-bash', name: 'Git Bash', executable: 'bash.exe');

    test('newLocalSession resolves the default shell via the resolver',
        () async {
      String? gotShell;
      p.localShell = LocalShellService(ptyFactory: (shell, a, c, r, env) {
        gotShell = shell;
        return _FakePty();
      });
      p.defaultShellResolver = () => (profile: gitBash, dangling: false);
      await p.newLocalSession();
      expect(gotShell, 'bash.exe');
    });

    test('explicit profile bypasses the resolver', () async {
      String? gotShell;
      p.localShell = LocalShellService(ptyFactory: (shell, a, c, r, env) {
        gotShell = shell;
        return _FakePty();
      });
      var resolverCalled = false;
      p.defaultShellResolver = () {
        resolverCalled = true;
        return (profile: null, dangling: false);
      };
      await p.newLocalSession(profile: gitBash);
      expect(gotShell, 'bash.exe');
      expect(resolverCalled, false);
    });

    test('platformDefault bypasses the resolver', () async {
      var resolverCalled = false;
      p.defaultShellResolver = () {
        resolverCalled = true;
        return (profile: gitBash, dangling: false);
      };
      await p.newLocalSession(platformDefault: true);
      expect(resolverCalled, false);
      final session = p.sessions.whereType<LocalSession>().single;
      expect(session.profile, isNull);
    });

    test('dangling default writes a yellow warning into the terminal',
        () async {
      p.defaultShellResolver = () => (profile: null, dangling: true);
      await p.newLocalSession();
      final session = p.sessions.whereType<LocalSession>().single;
      expect(session.terminal.buffer.getText(),
          contains('Default shell not found'));
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/providers/session_provider_local_test.dart`
Expected: COMPILE FAIL — `defaultShellResolver` / named params missing.

- [ ] **Step 3: Implement in `session_provider.dart`**

Add import `'../models/shell_profile.dart'`. Add field near `localShell`:

```dart
  /// Resolves the Settings default shell for new local terminals; wired by
  /// main.dart to SettingsProvider.resolveDefaultShell. Null (tests, early
  /// boot) behaves as platform default.
  ShellResolution Function()? defaultShellResolver;
```

Replace `newLocalSession`:

```dart
  Future<void> newLocalSession({
    ShellProfile? profile,
    bool platformDefault = false,
  }) async {
    final shell = localShell;
    if (shell == null) return;
    var chosen = profile;
    var dangling = false;
    if (chosen == null && !platformDefault) {
      final res = defaultShellResolver?.call();
      chosen = res?.profile;
      dangling = res?.dangling ?? false;
    }
    final session = await shell.openShell(profile: chosen);
    if (dangling) {
      session.terminal.write(
          '\x1b[33m[Default shell not found — using platform default. '
          'Check Settings → Terminal.]\x1b[0m\r\n');
    }
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/providers/session_provider_local_test.dart`
Expected: PASS (all existing + 4 new)

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_local_test.dart
git commit -m "feat: newLocalSession resolves default shell, warns on dangling id"
```

---

### Task 6: Startup wiring in `main.dart`

**Files:**
- Modify: `app/lib/main.dart` (near line 189, where `_sessionProvider.localShell = _localShell;` is)

- [ ] **Step 1: Wire detection + resolver**

Add imports:

```dart
import 'services/shell_detection.dart';
```

After `_sessionProvider.localShell = _localShell;` (and after `_settingsProvider = SettingsProvider();` has run — it's at line ~185):

```dart
    _sessionProvider.defaultShellResolver =
        _settingsProvider.resolveDefaultShell;
    // Fire-and-forget: the picker shows whatever has loaded; custom profiles
    // and the platform default are available immediately.
    unawaited(detectShells().then(_settingsProvider.setDetectedShells));
```

(`unawaited` is already imported in main.dart via `dart:async`; verify and add `import 'dart:async';` if missing.)

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: detect installed shells at startup, wire default-shell resolver"
```

---

### Task 7: Settings UI — default shell + custom shells

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart` (Terminal `_Section`, ~line 104)

- [ ] **Step 1: Add the dropdown + custom-shell management**

Add imports at top of `settings_screen.dart`:

```dart
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path_util;
import 'package:uuid/uuid.dart';
import '../models/shell_profile.dart';
```

Inside the Terminal `_Section`'s `children`, after the `terminalType` `_Row` (before `TerminalAppearanceControls`):

```dart
                  Consumer<SettingsProvider>(
                    builder: (context, settings, _) {
                      const platformDefault = '__platform_default__';
                      final profiles = settings.allShellProfiles;
                      final ids = {for (final s in profiles) s.id};
                      final value = settings.defaultShellId != null &&
                              ids.contains(settings.defaultShellId)
                          ? settings.defaultShellId!
                          : platformDefault;
                      return _Row(
                        label: 'Default local shell',
                        subtitle: 'Shell used by new local terminals',
                        trailing: _DropDown<String>(
                          value: value,
                          items: [
                            platformDefault,
                            for (final s in profiles) s.id,
                          ],
                          labelOf: (id) => id == platformDefault
                              ? 'Platform default'
                              : profiles.firstWhere((s) => s.id == id).name,
                          onChanged: (id) =>
                              context.read<SettingsProvider>().setDefaultShellId(
                                  id == platformDefault ? null : id),
                        ),
                      );
                    },
                  ),
                  const _CustomShellsRows(),
```

Add the widget + dialog near the other private widgets at the bottom of the file:

```dart
// ── Custom local shells (Settings → Terminal) ─────────────

class _CustomShellsRows extends StatelessWidget {
  const _CustomShellsRows();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final shell in settings.customShellProfiles)
          _Row(
            label: shell.name,
            subtitle: [shell.executable, ...shell.args].join(' '),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: AppColors.textSecondary),
              tooltip: 'Remove custom shell',
              onPressed: () => context
                  .read<SettingsProvider>()
                  .removeCustomShellProfile(shell.id),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add custom shell…',
                style: TextStyle(fontSize: 12)),
            onPressed: () => _showAddCustomShellDialog(context),
          ),
        ),
      ],
    );
  }
}

Future<void> _showAddCustomShellDialog(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  final nameCtrl = TextEditingController();
  final exeCtrl = TextEditingController();
  final argsCtrl = TextEditingController();
  final added = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Add custom shell', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: exeCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Executable path'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 16),
                tooltip: 'Browse…',
                onPressed: () async {
                  final file = await openFile();
                  if (file != null) exeCtrl.text = file.path;
                },
              ),
            ]),
            TextField(
              controller: argsCtrl,
              decoration: const InputDecoration(
                labelText: 'Arguments',
                helperText: 'Space-separated; quoting not supported',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add')),
      ],
    ),
  );
  final exe = exeCtrl.text.trim();
  if (added == true && exe.isNotEmpty) {
    final name = nameCtrl.text.trim();
    final argsText = argsCtrl.text.trim();
    await settings.addCustomShellProfile(ShellProfile(
      id: 'custom-${const Uuid().v4()}',
      name: name.isEmpty ? path_util.basename(exe) : name,
      executable: exe,
      args: argsText.isEmpty ? const [] : argsText.split(RegExp(r'\s+')),
      isCustom: true,
    ));
  }
  nameCtrl.dispose();
  exeCtrl.dispose();
  argsCtrl.dispose();
}
```

Note: `_Row` and `_DropDown` already exist in this file (lines ~1182/~1214); check `_Row` exposes a `subtitle` param (it's used at line 107) — it does.

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat: settings UI for default local shell + custom shells"
```

---

### Task 8: New-tab menu shell picker (`main_screen.dart`)

**Files:**
- Modify: `app/lib/screens/main_screen.dart` — `_TopTabBar` (~line 1071), `_AddTabBtn` (~line 1205), `onAddLocalSession` call site (~line 551)

- [ ] **Step 1: Change the callback signature and thread it**

Add import:

```dart
import '../models/shell_profile.dart';
```

In `_TopTabBar` (~line 1071):

```dart
  final void Function({ShellProfile? profile, bool platformDefault})
      onAddLocalSession;
```

In the `MainScreen` build call site (~line 551):

```dart
            onAddLocalSession: ({ShellProfile? profile,
                bool platformDefault = false}) {
              setState(() => _viewingTerminal = true);
              unawaited(context.read<SessionProvider>().newLocalSession(
                  profile: profile, platformDefault: platformDefault));
            },
```

- [ ] **Step 2: Extend `_AddTabBtn`**

```dart
class _AddTabBtn extends StatefulWidget {
  final VoidCallback onNewSsh;
  final void Function({ShellProfile? profile, bool platformDefault}) onNewLocal;
  const _AddTabBtn({required this.onNewSsh, required this.onNewLocal});

  @override
  State<_AddTabBtn> createState() => _AddTabBtnState();
}
```

In `_AddTabBtnState._showAddMenu`, read profiles and extend the menu (same set as the Settings dropdown: platform default + detected + custom):

```dart
  Future<void> _showAddMenu() async {
    final profiles = context.read<SettingsProvider>().allShellProfiles;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height));
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          origin.dx, origin.dy, origin.dx + 1, origin.dy + 1),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        const PopupMenuItem(
          value: 'ssh',
          child: Row(children: [
            Icon(Icons.dns_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('New SSH session',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        const PopupMenuItem(
          value: 'local',
          child: Row(children: [
            Icon(Icons.laptop_mac, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('New local terminal',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        if (profiles.isNotEmpty) const PopupMenuDivider(height: 4),
        if (profiles.isNotEmpty)
          const PopupMenuItem(
            value: 'shell:__platform__',
            child: Row(children: [
              Icon(Icons.terminal, size: 14, color: Color(0xFFAAAAAA)),
              SizedBox(width: 8),
              Text('Platform default shell',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
            ]),
          ),
        for (final s in profiles)
          PopupMenuItem(
            value: 'shell:${s.id}',
            child: Row(children: [
              const Icon(Icons.terminal, size: 14, color: Color(0xFFAAAAAA)),
              const SizedBox(width: 8),
              Text(s.name,
                  style: const TextStyle(
                      color: Color(0xFFCCCCCC), fontSize: 13)),
            ]),
          ),
      ],
    );
    if (result == null) return;
    if (result == 'ssh') {
      widget.onNewSsh();
    } else if (result == 'local') {
      widget.onNewLocal();
    } else if (result == 'shell:__platform__') {
      widget.onNewLocal(platformDefault: true);
    } else if (result.startsWith('shell:')) {
      final id = result.substring('shell:'.length);
      widget.onNewLocal(profile: profiles.firstWhere((s) => s.id == id));
    }
  }
```

(`SettingsProvider` import already exists in main_screen.dart — verify; add `import '../providers/settings_provider.dart';` if missing.)

- [ ] **Step 3: Analyze + full test run**

Run: `cd app && flutter analyze && flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: shell picker in the new-tab menu"
```

---

### Task 9: Final verification

- [ ] **Step 1: Full analyze + test suite**

Run: `cd app && flutter analyze && flutter test`
Expected: No analyzer issues; full suite green.

- [ ] **Step 2: Spec cross-check**

Re-read `docs/superpowers/specs/2026-06-06-local-shell-picker-design.md` §1–§7; confirm each requirement maps to shipped code (model ids, detection order, dangling fallback + warning, menu contents, error table, test list).

- [ ] **Step 3: Commit any leftovers**

```bash
git status --short   # should be clean; commit stragglers if any
```
