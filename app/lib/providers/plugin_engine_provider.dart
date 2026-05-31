import 'package:flutter/foundation.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

class PluginEngineProvider extends ChangeNotifier {
  final ScriptEngineService engine;
  final PluginLoader loader;
  final HookBus hookBus;
  final PluginUiRegistry uiRegistry;

  final _logs = <String, List<String>>{};
  PluginManifest? _pendingConsent;
  String? _pendingConsentDir;

  List<PluginManifest> get loadedPlugins => engine.loadedManifests;

  PluginEngineProvider({
    required this.engine,
    required this.loader,
    required this.hookBus,
    required this.uiRegistry,
  }) {
    engine.onChange = notifyListeners;
  }

  List<String> logsFor(String pluginId) =>
      List.unmodifiable(_logs[pluginId] ?? []);

  PluginManifest? get pendingConsent => _pendingConsent;
  String? get pendingConsentDir => _pendingConsentDir;

  void addLog(String pluginId, String message) {
    final list = _logs.putIfAbsent(pluginId, () => []);
    list.add(message);
    if (list.length > 200) list.removeAt(0);
    notifyListeners();
  }

  void setPendingConsent(
      String pluginId, PluginManifest manifest, String dir) {
    _pendingConsent = manifest;
    _pendingConsentDir = dir;
    notifyListeners();
  }

  Future<void> approveConsent(Set<String> granted) async {
    final m = _pendingConsent;
    final dir = _pendingConsentDir;
    _pendingConsent = null;
    _pendingConsentDir = null;
    notifyListeners();
    if (m != null && dir != null) {
      await loader.approvePermissions(m.id, granted, dir);
    }
  }

  void denyConsent() {
    _pendingConsent = null;
    _pendingConsentDir = null;
    notifyListeners();
  }

  @override
  void dispose() {
    engine.dispose();
    loader.dispose();
    super.dispose();
  }
}
