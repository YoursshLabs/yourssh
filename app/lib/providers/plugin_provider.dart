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

  PluginProvider({required this.plugins});

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
