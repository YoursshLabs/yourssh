import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// One-time move of app data out of the macOS App Sandbox container.
///
/// The app used to ship with `com.apple.security.app-sandbox`, which pointed
/// `HOME` at `~/Library/Containers/<bundle-id>/Data` and made every real user
/// folder (`~/Downloads`, `~/.ssh`, `~/Desktop`) unreadable — the sandbox only
/// exposes them as symlinks that raise `EPERM`. Now that the sandbox is gone,
/// `HOME` is the real home again, so prefs (hosts, keys, settings), the audit
/// database and disk-loaded JS plugins all resolve to *new*, empty locations.
/// This service copies the container's copies over on first unsandboxed launch.
///
/// Nothing here is required for correctness of a fresh install — it exists so
/// an update doesn't look like a factory reset. Every step is fail-soft: a
/// failure logs and moves on, and the marker is written either way so the
/// migration can't retry on every launch.
///
/// Deliberately *not* migrated:
/// - SSH keys and recordings under the container's `Documents/YourSSH` — prefs
///   store their absolute paths and an unsandboxed app can still read the
///   container, so copying would only duplicate private key material.
/// - Secrets in the Keychain — see `StorageService`; on ad-hoc-signed builds
///   the data-protection Keychain is unavailable in either configuration, so
///   the secrets in the migrated prefs are all there is to carry over.
class SandboxMigrationService {
  SandboxMigrationService({
    required this.homeRoot,
    required this.bundleId,
    PlistReader? readPlist,
  }) : readPlist = readPlist ?? _readPlistWithPlutil;

  /// Real (unsandboxed) home directory.
  final String homeRoot;
  final String bundleId;

  /// Reads a (possibly binary) plist as XML. Returns null when unreadable.
  final PlistReader readPlist;

  static const markerKey = 'macos_sandbox_migration_done';

  Future<SandboxMigrationResult> run(SharedPreferences prefs) async {
    if (prefs.getBool(markerKey) ?? false) {
      return const SandboxMigrationResult(reason: 'already-done');
    }
    final container =
        Directory(p.join(homeRoot, 'Library', 'Containers', bundleId, 'Data'));
    if (!container.existsSync()) {
      await prefs.setBool(markerKey, true);
      return const SandboxMigrationResult(reason: 'no-container');
    }

    final prefKeys = await _migratePrefs(prefs, container);
    final copied = [
      // Audit database (`getApplicationSupportDirectory`).
      ..._copyMissing(
        Directory(p.join(container.path, 'Library', 'Application Support', bundleId)),
        Directory(p.join(homeRoot, 'Library', 'Application Support', bundleId)),
      ),
      // Disk-loaded JS plugins (`~/.yourssh/plugins`).
      ..._copyMissing(
        Directory(p.join(container.path, '.yourssh', 'plugins')),
        Directory(p.join(homeRoot, '.yourssh', 'plugins')),
      ),
    ];

    await prefs.setBool(markerKey, true);
    debugPrint('[SandboxMigration] $prefKeys pref keys, '
        '${copied.length} files copied out of the sandbox container');
    return SandboxMigrationResult(prefKeys: prefKeys, copiedFiles: copied);
  }

  Future<int> _migratePrefs(
      SharedPreferences prefs, Directory container) async {
    final path =
        p.join(container.path, 'Library', 'Preferences', '$bundleId.plist');
    String? xml;
    try {
      xml = await readPlist(path);
    } catch (e) {
      debugPrint('[SandboxMigration] cannot read $path: $e');
    }
    if (xml == null) return 0;

    final plan =
        planPrefsMigration(parseXmlPlist(xml), existingKeys: prefs.getKeys());
    var written = 0;
    for (final entry in plan.entries) {
      final value = entry.value;
      try {
        if (value is String) {
          await prefs.setString(entry.key, value);
        } else if (value is bool) {
          await prefs.setBool(entry.key, value);
        } else if (value is int) {
          await prefs.setInt(entry.key, value);
        } else if (value is double) {
          await prefs.setDouble(entry.key, value);
        } else if (value is List<String>) {
          await prefs.setStringList(entry.key, value);
        } else {
          continue;
        }
        written++;
      } catch (e) {
        debugPrint('[SandboxMigration] pref ${entry.key} failed: $e');
      }
    }
    return written;
  }

  /// Copies [src] into [dst] recursively, never touching a path that already
  /// exists at the destination. Returns the destination paths written.
  List<String> _copyMissing(Directory src, Directory dst) {
    if (!src.existsSync()) return const [];
    final written = <String>[];
    try {
      for (final entity in src.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final target =
            File(p.join(dst.path, p.relative(entity.path, from: src.path)));
        if (target.existsSync()) continue;
        target.parent.createSync(recursive: true);
        entity.copySync(target.path);
        written.add(target.path);
      }
    } catch (e) {
      debugPrint('[SandboxMigration] copy ${src.path} → ${dst.path}: $e');
    }
    return written;
  }
}

typedef PlistReader = Future<String?> Function(String path);

Future<String?> _readPlistWithPlutil(String path) async {
  if (!File(path).existsSync()) return null;
  final result = await Process.run('plutil', ['-convert', 'xml1', '-o', '-', path]);
  if (result.exitCode != 0) return null;
  final xml = result.stdout;
  return xml is String && xml.isNotEmpty ? xml : null;
}

class SandboxMigrationResult {
  const SandboxMigrationResult({
    this.prefKeys = 0,
    this.copiedFiles = const [],
    this.reason,
  });

  final int prefKeys;
  final List<String> copiedFiles;

  /// Why nothing was migrated, when that's the case.
  final String? reason;

  bool get migrated => prefKeys > 0 || copiedFiles.isNotEmpty;
}

/// Maps a container plist onto the prefs keys to write, keyed the way
/// `SharedPreferences` sees them (the `flutter.` prefix is the plugin's own).
///
/// Keys already present are left alone: whatever the unsandboxed app has
/// written since the update is newer than the container's copy.
Map<String, Object?> planPrefsMigration(
  Map<String, Object?> plist, {
  required Set<String> existingKeys,
}) {
  const prefix = 'flutter.';
  final plan = <String, Object?>{};
  for (final entry in plist.entries) {
    if (!entry.key.startsWith(prefix)) continue;
    final key = entry.key.substring(prefix.length);
    if (key.isEmpty || existingKeys.contains(key)) continue;
    plan[key] = entry.value;
  }
  return plan;
}

/// Parses the top-level dictionary of an XML property list.
///
/// Only the value types `shared_preferences` can hold are kept (string, bool,
/// int, double, list-of-string); `<data>`, `<date>`, nested dicts and mixed
/// arrays — all of which are macOS's own container-only keys — are skipped
/// rather than guessed at. A malformed document yields an empty map.
Map<String, Object?> parseXmlPlist(String xml) {
  final dictStart = xml.indexOf('<dict>');
  if (dictStart < 0) return const {};
  final scanner = _PlistScanner(xml, dictStart + '<dict>'.length);
  return scanner.readDictBody();
}

/// Sentinel for a value this parser deliberately doesn't carry over.
const Object _unsupported = Object();

class _PlistScanner {
  _PlistScanner(this.src, this.pos);

  final String src;
  int pos;

  Map<String, Object?> readDictBody() {
    final out = <String, Object?>{};
    while (true) {
      final tag = _nextTag();
      if (tag == null || tag == '/dict') return out;
      if (tag != 'key') continue;
      final key = _readTextUntil('</key>');
      if (key == null) return out;
      final valueTag = _nextTag();
      if (valueTag == null) return out;
      final value = _readValue(valueTag);
      if (value != _unsupported) out[key] = value;
    }
  }

  /// Consumes up to and past the next `<...>`; returns its name (`/dict`,
  /// `true/` for self-closing) or null at end of input.
  String? _nextTag() {
    final open = src.indexOf('<', pos);
    if (open < 0) return null;
    final close = src.indexOf('>', open);
    if (close < 0) return null;
    pos = close + 1;
    final name = src.substring(open + 1, close);
    // Skip processing instructions / doctype / comments.
    if (name.startsWith('?') || name.startsWith('!')) return _nextTag();
    return name;
  }

  String? _readTextUntil(String closing) {
    final end = src.indexOf(closing, pos);
    if (end < 0) return null;
    final text = src.substring(pos, end);
    pos = end + closing.length;
    return _unescape(text);
  }

  Object? _readValue(String tag) {
    switch (tag) {
      case 'string':
        return _readTextUntil('</string>') ?? '';
      case 'string/':
        return '';
      case 'true/':
        return true;
      case 'false/':
        return false;
      case 'integer':
        return int.tryParse(_readTextUntil('</integer>')?.trim() ?? '') ??
            _unsupported;
      case 'real':
        return double.tryParse(_readTextUntil('</real>')?.trim() ?? '') ??
            _unsupported;
      case 'array':
        return _readStringArray();
      case 'array/':
        return const <String>[];
      case 'dict':
        _skipBalanced('dict');
        return _unsupported;
      default:
        // <data>, <date>, anything unknown: consume its closing tag if it has
        // one, then report it as skipped.
        if (!tag.endsWith('/')) _readTextUntil('</$tag>');
        return _unsupported;
    }
  }

  /// A list of `<string>`s, or [_unsupported] if the array holds anything else
  /// (`shared_preferences` only ever writes string lists).
  Object? _readStringArray() {
    final items = <String>[];
    while (true) {
      final tag = _nextTag();
      if (tag == null) return _unsupported;
      if (tag == '/array') return items;
      if (tag == 'string') {
        final text = _readTextUntil('</string>');
        if (text == null) return _unsupported;
        items.add(text);
        continue;
      }
      if (tag == 'string/') {
        items.add('');
        continue;
      }
      _readValue(tag);
      // Non-string member: drain the array and skip the key entirely.
      while (true) {
        final next = _nextTag();
        if (next == null || next == '/array') return _unsupported;
        _readValue(next);
      }
    }
  }

  void _skipBalanced(String tag) {
    var depth = 1;
    while (depth > 0) {
      final next = _nextTag();
      if (next == null) return;
      if (next == tag) {
        depth++;
      } else if (next == '/$tag') {
        depth--;
      }
    }
  }

  static String _unescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
