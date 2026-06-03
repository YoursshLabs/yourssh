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

    final files = <File>[];
    for (final dir in dirs) {
      if (dir.existsSync()) {
        files.addAll(dir
            .listSync()
            .whereType<File>()
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

  static Future<List<AppOption>> _queryWindows(String filePath) async {
    final ext = p.extension(filePath).toLowerCase(); // e.g. ".txt"
    if (ext.isEmpty) return [];

    // Query user OpenWithList (single-letter keys a, b, c… hold exe names)
    // then resolve each exe name to a full path via the ftype command.
    // This two-step approach handles apps not in PATH (most GUI apps).
    final psScript = r'''
param([string]$Ext)
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Ext\OpenWithList"
$props = Get-ItemProperty $key -ErrorAction SilentlyContinue
if ($props -eq $null) { exit 0 }
$props.PSObject.Properties |
  Where-Object { $_.Name -match '^[a-zA-Z]$' } |
  ForEach-Object { $_.Value }
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', psScript, '-Ext', ext],
    );
    if (result.exitCode != 0) return _queryWindowsFallback(ext);

    final exeNames = (result.stdout as String)
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.toLowerCase().endsWith('.exe'))
        .toSet() // dedup
        .toList();

    if (exeNames.isEmpty) return _queryWindowsFallback(ext);

    final apps = <AppOption>[];
    for (final exeName in exeNames) {
      // Try PATH first, then HKCR ftype for apps not in PATH.
      String? exePath = await _resolveWindowsExe(exeName);
      if (exePath == null) continue;

      final descScript =
          '[System.Diagnostics.FileVersionInfo]::GetVersionInfo(\'$exePath\').FileDescription';
      final descResult = await Process.run(
          'powershell', ['-NoProfile', '-Command', descScript]);
      final desc = (descResult.stdout as String).trim();
      apps.add(AppOption(
        name: desc.isNotEmpty ? desc : exeName.replaceFirst('.exe', ''),
        executablePath: exePath,
        isDefault: false,
      ));
    }
    return apps;
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
    // 2. Scan HKCR open commands for matching exe name
    final psScript =
        r'Get-ChildItem "HKCR:\*\shell\open\command" -ErrorAction SilentlyContinue | '
        'ForEach-Object { (Get-ItemProperty \$_.PsPath)."(default)" } | '
        'Where-Object { \$_ -like "*${exeName.replaceAll(r'\', r'\\')}*" } | '
        'Select-Object -First 1';
    final regResult = await Process.run(
        'powershell', ['-NoProfile', '-Command', psScript]);
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
