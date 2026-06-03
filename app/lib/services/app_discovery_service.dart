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

  /// Returns apps that can open [filePath], cached by extension.
  /// Never throws — returns [] on any platform error.
  Future<List<AppOption>> getAppsFor(String filePath) async {
    final ext = p.extension(filePath).toLowerCase(); // e.g. ".txt"
    if (_cache.containsKey(ext)) return _cache[ext]!;
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

  /// HKCR: is not a default PSDrive in powershell.exe (only HKLM:/HKCU: are),
  /// so the scan uses the provider-qualified path, which needs no drive
  /// mounted. Single quotes in [exeName] are doubled for the PS literal.
  @visibleForTesting
  static String windowsResolveExeScript(String exeName) {
    final escaped = exeName.replaceAll("'", "''");
    return r'Get-ChildItem "Registry::HKEY_CLASSES_ROOT\*\shell\open\command" '
        r'-ErrorAction SilentlyContinue | '
        r'ForEach-Object { (Get-ItemProperty $_.PsPath)."(default)" } | '
        "Where-Object { \$_ -like ('*' + '$escaped' + '*') } | "
        'Select-Object -First 1';
  }

  /// Single quotes in [exePath] are doubled so paths like `C:\O'Brien` don't
  /// terminate the PS string literal.
  @visibleForTesting
  static String windowsFileDescriptionScript(String exePath) {
    final escaped = exePath.replaceAll("'", "''");
    return "[System.Diagnostics.FileVersionInfo]::GetVersionInfo('$escaped')"
        '.FileDescription';
  }

  static Future<List<AppOption>> _queryWindows(String filePath) async {
    final ext = p.extension(filePath).toLowerCase(); // e.g. ".txt"
    // Empty result makes getAppsFor fall back to the .txt editor list.
    if (!isSafeWindowsExtension(ext)) return [];

    // Query user OpenWithList (single-letter keys a, b, c… hold exe names)
    // then resolve each exe name to a full path via the registry.
    // This two-step approach handles apps not in PATH (most GUI apps).
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
        .where((s) => s.isNotEmpty && s.toLowerCase().endsWith('.exe'))
        .toSet() // dedup
        .toList();

    if (exeNames.isEmpty) return _queryWindowsFallback(ext);

    // Resolve paths and descriptions concurrently — each lookup spawns a
    // PowerShell process, and doing them in sequence made the first menu
    // open take seconds.
    final options = await Future.wait(exeNames.map(_windowsAppOption));
    return options.whereType<AppOption>().toList();
  }

  static Future<AppOption?> _windowsAppOption(String exeName) async {
    // Try PATH first, then the HKCR open commands for apps not in PATH.
    final exePath = await _resolveWindowsExe(exeName);
    if (exePath == null) return null;

    final descResult = await Process.run('powershell',
        ['-NoProfile', '-Command', windowsFileDescriptionScript(exePath)]);
    final desc = (descResult.stdout as String).trim();
    return AppOption(
      name: desc.isNotEmpty ? desc : exeName.replaceFirst('.exe', ''),
      executablePath: exePath,
      isDefault: false,
    );
  }

  /// Resolves an exe filename (e.g. "notepad.exe") to a full path.
  /// Tries PATH lookup first, then scans HKCR for a matching open command.
  static Future<String?> _resolveWindowsExe(String exeName) async {
    // 1. Try where.exe (finds apps in PATH)
    final whereResult =
        await Process.run('where', [exeName], runInShell: true);
    if (whereResult.exitCode == 0) {
      final path = (whereResult.stdout as String).split('\n').first.trim();
      if (path.isNotEmpty && File(path).existsSync()) return path;
    }
    // 2. Scan HKEY_CLASSES_ROOT open commands for matching exe name
    final regResult = await Process.run('powershell',
        ['-NoProfile', '-Command', windowsResolveExeScript(exeName)]);
    if (regResult.exitCode != 0) return null;
    final cmd = (regResult.stdout as String).trim();
    // Extract quoted path from e.g. '"C:\Program Files\Notepad++\notepad++.exe" "%1"'
    final match = RegExp(r'"([^"]+\.exe)"').firstMatch(cmd);
    final path = match?.group(1);
    if (path != null && File(path).existsSync()) return path;
    return null;
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
