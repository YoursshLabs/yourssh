// app/lib/services/app_discovery_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
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

  /// Lookups still running, keyed by extension. A platform query can take a
  /// second or more (it shells out), and the cache is only populated once it
  /// finishes — without this, right-clicking a handful of files of the same
  /// unseen type fires one full discovery each and floods the machine with
  /// processes (issue #88).
  final _inFlight = <String, Future<List<AppOption>>>{};

  /// Returns apps that can open [filePath], cached by extension.
  /// Never throws — returns [] on any platform error.
  Future<List<AppOption>> getAppsFor(String filePath) {
    final ext = p.extension(filePath).toLowerCase(); // e.g. ".txt"
    final cached = _cache[ext];
    if (cached != null) return Future.value(cached);
    return _inFlight[ext] ??= _discover(filePath, ext)
      ..whenComplete(() => _inFlight.remove(ext));
  }

  Future<List<AppOption>> _discover(String filePath, String ext) async {
    try {
      var apps = await _probeAndQuery(filePath, ext);
      // No OS-registered handler for this extension (.conf, .service, …).
      // In an SSH context such files are almost always plain text, so fall
      // back to the text-editor list registered for .txt.
      if (apps.isEmpty && ext != '.txt') {
        apps = await getAppsFor('fallback.txt');
      }
      _cache[ext] = apps;
      return apps;
    } catch (_) {
      return [];
    }
  }

  /// Runs the platform querier; materializes an empty probe file first when
  /// [filePath] does not exist — macOS Launch Services and Linux xdg-mime
  /// return nothing for nonexistent paths.
  Future<List<AppOption>> _probeAndQuery(String filePath, String ext) async {
    var queryPath = filePath;
    File? probe;
    if (!File(filePath).existsSync()) {
      probe = File('${Directory.systemTemp.path}/yourssh_probe$ext')
        ..createSync();
      queryPath = probe.path;
    }
    final apps = await _querier(queryPath);
    if (probe != null && probe.existsSync()) probe.deleteSync();
    return apps;
  }

  void dispose() {
    _cache.clear();
    _inFlight.clear();
  }

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
    final raw = await _channel
        .invokeListMethod<List<Object?>>('getAppsFor', {'path': filePath});
    if (raw == null) return [];
    return raw.map((entry) {
      final list = entry.cast<String>();
      return AppOption(
        name: list[0],
        executablePath: list[2],
        iconPath: list[3].isEmpty ? null : list[3],
        isDefault: false,
      );
    }).toList();
  }

  // ── Linux ─────────────────────────────────────────────────────────────────

  static Future<List<AppOption>> _queryLinux(String filePath) async {
    final mimeResult =
        await Process.run('xdg-mime', ['query', 'filetype', filePath]);
    if (mimeResult.exitCode != 0) return [];
    final mimeType = (mimeResult.stdout as String).trim();

    final defaultResult =
        await Process.run('xdg-mime', ['query', 'default', mimeType]);
    final defaultFile = (defaultResult.stdout as String).trim();

    final dirs = [
      Directory(p.join(
          Platform.environment['HOME'] ?? '', '.local', 'share', 'applications')),
      Directory('/usr/share/applications'),
      Directory('/usr/local/share/applications'),
    ];

    // Async I/O throughout — a system can have 100+ .desktop files and this
    // runs on the UI isolate.
    final files = <File>[];
    for (final dir in dirs) {
      if (await dir.exists()) {
        files.addAll((await dir.list().toList())
            .whereType<File>()
            .where((f) => f.path.endsWith('.desktop')));
      }
    }

    return parseDesktopFiles(
        files: files, mimeType: mimeType, defaultDesktopFile: defaultFile);
  }

  /// Exposed for unit testing without spawning processes.
  static Future<List<AppOption>> parseDesktopFiles({
    required List<File> files,
    required String mimeType,
    required String defaultDesktopFile,
  }) async {
    final result = <AppOption>[];
    for (final file in files) {
      try {
        final lines = await file.readAsLines();
        String? name, exec, mimeTypes;
        for (final line in lines) {
          if (line.startsWith('Name=') && name == null) {
            name = line.substring(5).trim();
          }
          if (line.startsWith('Exec=')) exec = line.substring(5).trim();
          if (line.startsWith('MimeType=')) {
            mimeTypes = line.substring(9).trim();
          }
        }
        if (name == null || exec == null || mimeTypes == null) continue;
        if (!mimeTypes.split(';').map((s) => s.trim()).contains(mimeType)) {
          continue;
        }

        // Strip all XDG Exec field code placeholders (%f, %F, %u, %U, %d,
        // %D, %n, %N, %i, %c, %k, %v, %m) per the Desktop Entry spec.
        // Replace %% with a literal percent sign.
        final cleanExec = exec
            .replaceAll('%%', '\x00') // protect literal % temporarily
            .replaceAll(RegExp(r'\s*%[a-zA-Z]\s*'), '')
            .replaceAll('\x00', '%')
            .trim();
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

  /// Extensions come from remote SFTP filenames — untrusted input that gets
  /// interpolated into PowerShell / cmd command lines. Only a conservative
  /// charset is allowed through.
  @visibleForTesting
  static bool isSafeWindowsExtension(String ext) =>
      RegExp(r'^\.[a-z0-9_+\-]+$').hasMatch(ext);

  /// powershell.exe joins everything after `-Command` into the command text,
  /// so named args after the script string never bind to `param()` — the
  /// (validated) extension is interpolated instead.
  @visibleForTesting
  static String windowsOpenWithListScript(String ext) => '''
\$key = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\$ext\\OpenWithList"
\$props = Get-ItemProperty \$key -ErrorAction SilentlyContinue
if (\$props -eq \$null) { exit 0 }
\$props.PSObject.Properties |
  Where-Object { \$_.Name -match '^[a-zA-Z]\$' } |
  ForEach-Object { \$_.Value }
''';

  /// Resolves a batch of exe names to tab-separated `name`, `path`,
  /// `description` lines in a single PowerShell process, using direct
  /// registry key lookups only.
  ///
  /// The previous implementation ran, per app, one
  /// `Get-ChildItem "Registry::HKEY_CLASSES_ROOT\*\shell\open\command"` — a
  /// wildcard enumeration of every class in HKCR (thousands of keys, each
  /// followed by a `Get-ItemProperty`) — plus a second process for the file
  /// description. With the OpenWithList apps resolved concurrently that is
  /// `1 + 2N` PowerShell processes all churning the registry at once, which
  /// pinned the CPU at 100% and froze the app (issue #88).
  ///
  /// The lookups below are O(1) key reads instead:
  ///   1. `App Paths\<exe>` — where installers register GUI apps.
  ///   2. `HKCR\Applications\<exe>\shell\open\command` — the same open
  ///      command the old scan was searching for, addressed directly.
  ///   3. `Get-Command` — apps on PATH.
  ///
  /// HKCR: is not a default PSDrive in powershell.exe (only HKLM:/HKCU:
  /// are), so `Registry::HKEY_CLASSES_ROOT` is used — it needs no drive
  /// mounted. Single quotes in the names are doubled for the PS literals,
  /// and results go out through `[Console]::Out` rather than
  /// `Write-Output` — the formatting pipeline soft-wraps at the host
  /// buffer width, which would split long install paths across lines.
  @visibleForTesting
  static String windowsResolveAppsScript(Iterable<String> exeNames) {
    final names =
        exeNames.map((n) => "'${n.replaceAll("'", "''")}'").join(',');
    return '''
\$ErrorActionPreference = 'SilentlyContinue'
\$names = @($names)
\$appPaths = @(
  'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths',
  'HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\App Paths',
  'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths')
foreach (\$n in \$names) {
  \$path = \$null
  foreach (\$root in \$appPaths) {
    \$v = (Get-ItemProperty -LiteralPath (\$root + '\\' + \$n))."(default)"
    if (\$v) { \$path = \$v.Trim('"'); break }
  }
  if (-not \$path) {
    \$cmd = (Get-ItemProperty -LiteralPath ('Registry::HKEY_CLASSES_ROOT\\Applications\\' + \$n + '\\shell\\open\\command'))."(default)"
    if (\$cmd -match '"([^"]+\\.exe)"') { \$path = \$Matches[1] }
    elseif (\$cmd -match '([^\\s"]+\\.exe)') { \$path = \$Matches[1] }
  }
  if (-not \$path) {
    \$c = @(Get-Command -Name \$n -CommandType Application)
    if (\$c.Count -gt 0) { \$path = \$c[0].Source }
  }
  if (-not \$path) { continue }
  \$path = [System.Environment]::ExpandEnvironmentVariables(\$path)
  if (-not (Test-Path -LiteralPath \$path -PathType Leaf)) { continue }
  \$desc = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(\$path).FileDescription
  [Console]::Out.WriteLine(\$n + [char]9 + \$path + [char]9 + \$desc)
}
''';
  }

  /// Exe names come out of the registry but still end up interpolated into a
  /// PowerShell literal, so anything outside a plain filename charset is
  /// dropped rather than escaped.
  @visibleForTesting
  static bool isSafeWindowsExeName(String name) =>
      RegExp(r"^[\w .+\-()']+\.exe$").hasMatch(name.toLowerCase());

  /// Parses the tab-separated lines produced by [windowsResolveAppsScript],
  /// falling back to the exe name when the binary carries no FileDescription.
  @visibleForTesting
  static List<AppOption> parseWindowsResolvedApps(String stdout) {
    final options = <AppOption>[];
    for (final line in stdout.split('\n')) {
      final parts = line.trim().split('\t');
      if (parts.length < 2) continue;
      final name = parts[0].trim();
      final path = parts[1].trim();
      if (name.isEmpty || path.isEmpty) continue;
      final desc = parts.length > 2 ? parts[2].trim() : '';
      options.add(AppOption(
        name: desc.isNotEmpty ? desc : name.replaceFirst('.exe', ''),
        executablePath: path,
        isDefault: false,
      ));
    }
    return options;
  }

  /// Upper bound on apps resolved per extension. OpenWithList holds a
  /// handful in practice; the cap keeps a corrupt key from generating an
  /// unbounded script.
  static const _maxWindowsApps = 16;

  static Future<List<AppOption>> _queryWindows(String filePath) async {
    final ext = p.extension(filePath).toLowerCase(); // e.g. ".txt"
    // Empty result makes getAppsFor fall back to the .txt editor list.
    if (!isSafeWindowsExtension(ext)) return [];

    // Two PowerShell processes total: read the user's OpenWithList, then
    // resolve every exe in it to a path + description in one batch.
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        windowsOpenWithListScript(ext),
      ],
    );
    if (result.exitCode != 0) return _queryWindowsFallback(ext);

    final exeNames = (result.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.toLowerCase().endsWith('.exe'))
        .where(isSafeWindowsExeName)
        .toSet() // dedup
        .take(_maxWindowsApps)
        .toList();

    if (exeNames.isEmpty) return _queryWindowsFallback(ext);

    final resolved = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      windowsResolveAppsScript(exeNames),
    ]);
    if (resolved.exitCode != 0) return _queryWindowsFallback(ext);

    final options = parseWindowsResolvedApps(resolved.stdout as String);
    return options.isEmpty ? _queryWindowsFallback(ext) : options;
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

    final ftypeResult = await Process.run(
        'cmd', ['/c', 'ftype', progId], runInShell: true);
    if (ftypeResult.exitCode != 0) return [];
    final ftypeLine =
        (ftypeResult.stdout as String).split('=').skip(1).join('=').trim();
    final exePath =
        ftypeLine.split('"').where((s) => s.endsWith('.exe')).firstOrNull;
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
