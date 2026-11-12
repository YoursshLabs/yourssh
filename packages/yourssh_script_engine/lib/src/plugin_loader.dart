import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';
import 'plugin_manifest.dart';
import 'plugin_paths.dart';
import 'script_engine_service.dart';
import 'bridge/storage_bridge.dart';

const _kPermKey = 'plugin::permissions::';
const _kHashKey = 'plugin::hash::';

/// SHA-256 over every regular file in [pluginDir] (relative path + bytes,
/// sorted), so consent is bound to the exact manifest, entry script and any
/// panel assets that were shown to the user.
String hashPluginDir(String pluginDir) {
  final root = Directory(pluginDir);
  final entries = root
      .listSync(recursive: true, followLinks: false)
      .where((e) => e is File || e is Link)
      .map((e) => e.path)
      .toList()
    ..sort();
  final buf = BytesBuilder();
  for (final path in entries) {
    final rel = path.substring(root.path.length);
    buf.add(utf8.encode('F:$rel\n'));
    if (FileSystemEntity.isLinkSync(path)) {
      // A symlink is hashed by its target so retargeting changes the hash.
      buf.add(utf8.encode('L:${Link(path).targetSync()}\n'));
    } else {
      final bytes = File(path).readAsBytesSync();
      buf.add(utf8.encode('S:${bytes.length}\n'));
      buf.add(bytes);
    }
  }
  return sha256.convert(buf.takeBytes()).toString();
}

class PluginLoader {
  final ScriptEngineService _engine;
  final void Function(String pluginId, PluginManifest manifest, String pluginDir)
      onConsentRequired;
  final void Function(String pluginId, String message) onError;

  StreamSubscription<WatchEvent>? _watchSub;

  /// Content hash shown to the user when consent was requested, per plugin id.
  final _pendingHashes = <String, String>{};

  PluginLoader({
    required ScriptEngineService engine,
    required this.onConsentRequired,
    required this.onError,
  }) : _engine = engine;

  Future<void> scanAndLoad() async {
    await StorageBridge.warmup();
    final dir = _pluginsDir();
    if (!dir.existsSync()) return;

    for (final entity in dir.listSync()) {
      if (entity is Directory) await _tryLoad(entity.path);
    }

    _watchSub = DirectoryWatcher(dir.path).events.listen(_onWatchEvent);
  }

  Future<void> approvePermissions(
      String pluginId, Set<String> granted, String pluginDir) async {
    final String currentHash;
    PluginManifest manifest;
    try {
      manifest = PluginManifest.fromJson(
          await File('$pluginDir/plugin.json').readAsString());
      currentHash = hashPluginDir(pluginDir);
    } catch (e) {
      onError(pluginId, 'Load failed after approval: $e');
      return;
    }
    final approvedHash = _pendingHashes.remove(pluginId);
    if (approvedHash != null && approvedHash != currentHash) {
      // Files changed between the prompt and the approval.
      onError(pluginId, 'Plugin changed while awaiting approval; reloading');
      await tryLoad(pluginDir);
      return;
    }
    final effective = granted.intersection(manifest.permissions);
    await _saveConsent(pluginId, effective, currentHash);
    try {
      await _engine.loadPlugin(pluginDir, grantedPermissions: effective);
    } catch (e) {
      onError(pluginId, 'Load failed after approval: $e');
    }
  }

  Future<void> _tryLoad(String pluginDir) => tryLoad(pluginDir);

  /// Loads the plugin in [pluginDir], asking for consent when it is new, its
  /// content changed since approval, or it declares permissions never granted.
  @visibleForTesting
  Future<void> tryLoad(String pluginDir) async {
    final manifestFile = File('$pluginDir/plugin.json');
    if (!manifestFile.existsSync()) return;

    PluginManifest manifest;
    try {
      manifest = PluginManifest.fromJson(await manifestFile.readAsString());
    } catch (e) {
      onError(pluginDir, 'Invalid manifest: $e');
      return;
    }

    if (resolvePluginFile(pluginDir, manifest.entry) == null) {
      onError(manifest.id,
          'Entry "${manifest.entry}" is missing or outside the plugin directory');
      return;
    }

    String currentHash;
    try {
      currentHash = hashPluginDir(pluginDir);
    } catch (e) {
      onError(manifest.id, 'Cannot read plugin files: $e');
      return;
    }

    // Stale grants (permissions the manifest no longer declares) never apply.
    final stored = await _loadPerms(manifest.id);
    final granted = stored.intersection(manifest.permissions);
    final storedHash = await _loadHash(manifest.id);
    final needsConsent = manifest.permissions.isNotEmpty &&
        (storedHash != currentHash || _hasNewPerms(manifest, granted));
    if (needsConsent) {
      _pendingHashes[manifest.id] = currentHash;
      onConsentRequired(manifest.id, manifest, pluginDir);
      return;
    }

    try {
      await _engine.loadPlugin(pluginDir, grantedPermissions: granted);
    } catch (e) {
      onError(manifest.id, 'Load failed: $e');
    }
  }

  void _onWatchEvent(WatchEvent event) {
    // Any file inside a plugin directory (script, manifest, panel assets)
    // is part of the consented content, so any change re-evaluates the plugin.
    final dir = _pluginsDir().path;
    final path = event.path;
    if (!path.startsWith('$dir${Platform.pathSeparator}')) return;
    final rel = path.substring(dir.length + 1);
    final sep = rel.indexOf(Platform.pathSeparator);
    if (sep <= 0) return;
    final pluginDir = '$dir${Platform.pathSeparator}${rel.substring(0, sep)}';
    final id = _readPluginId(pluginDir);
    if (id == null) return;

    _engine.unloadPlugin(id);
    _tryLoad(pluginDir).catchError((_) {});
  }

  String? _readPluginId(String pluginDir) {
    final f = File('$pluginDir/plugin.json');
    if (!f.existsSync()) return null;
    try {
      return PluginManifest.fromJson(f.readAsStringSync()).id;
    } catch (_) {
      return null;
    }
  }

  bool _hasNewPerms(PluginManifest manifest, Set<String> granted) =>
      manifest.permissions.any((p) => !granted.contains(p));

  Future<Set<String>> _loadPerms(String pluginId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('$_kPermKey$pluginId')?.toSet() ?? {};
  }

  Future<String?> _loadHash(String pluginId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_kHashKey$pluginId');
  }

  Future<void> _saveConsent(
      String pluginId, Set<String> granted, String hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_kPermKey$pluginId', granted.toList());
    await prefs.setString('$_kHashKey$pluginId', hash);
  }

  Directory _pluginsDir() {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']!
        : Platform.environment['HOME']!;
    return Directory('$home/.yourssh/plugins');
  }

  void dispose() {
    _watchSub?.cancel();
  }
}
