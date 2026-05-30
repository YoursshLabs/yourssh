import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';

class PluginProvider extends ChangeNotifier {
  final List<YourSSHPlugin> plugins;

  /// Optional callback called when a plugin is toggled.
  /// Receives the plugin and whether it was enabled (true) or disabled (false).
  /// Use this to call plugin.onActivate / onDeactivate from the UI layer.
  void Function(YourSSHPlugin plugin, bool enabled)? onToggled;

  Set<String> _enabledIds = {};

  PluginProvider({required this.plugins}) {
    _checkCompatibility();
  }

  void _checkCompatibility() {
    for (final plugin in plugins) {
      if (!_isCompatible(plugin.minApiVersion)) {
        debugPrint(
          '[PluginProvider] Warning: plugin "${plugin.id}" requires API '
          '${plugin.minApiVersion} but host provides $kYourSSHPluginApiVersion. '
          'Plugin may not function correctly.',
        );
      }
    }
  }

  bool _isCompatible(String minVersion) {
    // Simple major.minor.patch comparison — no semver library needed yet
    try {
      final host = kYourSSHPluginApiVersion.split('.').map(int.parse).toList();
      final req = minVersion.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final h = i < host.length ? host[i] : 0;
        final r = i < req.length ? req[i] : 0;
        if (h > r) return true;
        if (h < r) return false;
      }
      return true; // equal
    } catch (_) {
      debugPrint('[PluginProvider] Warning: invalid minApiVersion format: "$minVersion"');
      return false;
    }
  }

  List<YourSSHPlugin> get enabledPlugins =>
      plugins.where((p) => _enabledIds.contains(p.id)).toList();

  bool isEnabled(String pluginId) => _enabledIds.contains(pluginId);

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('enabled_plugins') ?? [];
    _enabledIds = saved.toSet();
    notifyListeners();
  }

  Future<void> toggle(String pluginId) async {
    final wasEnabled = _enabledIds.contains(pluginId);
    wasEnabled ? _enabledIds.remove(pluginId) : _enabledIds.add(pluginId);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('enabled_plugins', _enabledIds.toList());
    final plugin = plugins.where((p) => p.id == pluginId).firstOrNull;
    if (plugin != null) onToggled?.call(plugin, !wasEnabled);
  }
}
