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
    final candidate =
        p.windows.join(programFiles, 'PowerShell', '7', 'pwsh.exe');
    if (exists(candidate)) pwsh = candidate;
  }
  if (pwsh != null) {
    profiles
        .add(ShellProfile(id: 'pwsh', name: 'PowerShell 7', executable: pwsh));
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
