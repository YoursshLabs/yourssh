import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';
import 'plugin_manifest.dart';
import 'script_engine_service.dart';
import 'bridge/storage_bridge.dart';

const _kPermKey = 'plugin::permissions::';

class PluginLoader {
  final ScriptEngineService _engine;
  final void Function(String pluginId, PluginManifest manifest, String pluginDir)
      onConsentRequired;
  final void Function(String pluginId, String message) onError;

  StreamSubscription<WatchEvent>? _watchSub;

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
    await _savePerms(pluginId, granted);
    try {
      await _engine.loadPlugin(pluginDir, grantedPermissions: granted);
    } catch (e) {
      onError(pluginId, 'Load failed after approval: $e');
    }
  }

  Future<void> _tryLoad(String pluginDir) async {
    final manifestFile = File('$pluginDir/plugin.json');
    if (!manifestFile.existsSync()) return;

    PluginManifest manifest;
    try {
      manifest = PluginManifest.fromJson(await manifestFile.readAsString());
    } catch (e) {
      onError(pluginDir, 'Invalid manifest: $e');
      return;
    }

    final granted = await _loadPerms(manifest.id);
    if (_hasNewPerms(manifest, granted)) {
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
    final path = event.path;
    if (!path.endsWith('.js') && !path.endsWith('plugin.json')) return;

    final pluginDir = File(path).parent.path;
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

  Future<void> _savePerms(String pluginId, Set<String> granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('$_kPermKey$pluginId', granted.toList());
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
