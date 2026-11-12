import 'package:flutter/foundation.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

class PluginEngineProvider extends ChangeNotifier {
  final ScriptEngineService engine;
  final PluginLoader loader;
  final HookBus hookBus;
  final PluginUiRegistry uiRegistry;

  final _logs = <String, List<String>>{};
  // Plugins waiting for consent, in arrival order; the dialog shows the head.
  final _pendingConsents = <({PluginManifest manifest, String dir})>[];

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

  PluginManifest? get pendingConsent =>
      _pendingConsents.isEmpty ? null : _pendingConsents.first.manifest;
  String? get pendingConsentDir =>
      _pendingConsents.isEmpty ? null : _pendingConsents.first.dir;

  void addLog(String pluginId, String message) {
    final list = _logs.putIfAbsent(pluginId, () => []);
    list.add(message);
    if (list.length > 200) list.removeAt(0);
    notifyListeners();
  }

  void setPendingConsent(
      String pluginId, PluginManifest manifest, String dir) {
    final index = _pendingConsents.indexWhere((p) => p.dir == dir);
    if (index >= 0) {
      _pendingConsents[index] = (manifest: manifest, dir: dir);
    } else {
      _pendingConsents.add((manifest: manifest, dir: dir));
    }
    notifyListeners();
  }

  Future<void> approveConsent(Set<String> granted) async {
    if (_pendingConsents.isEmpty) return;
    final head = _pendingConsents.removeAt(0);
    notifyListeners();
    await loader.approvePermissions(head.manifest.id, granted, head.dir);
  }

  void denyConsent() {
    if (_pendingConsents.isNotEmpty) _pendingConsents.removeAt(0);
    notifyListeners();
  }

  @override
  void dispose() {
    engine.dispose();
    loader.dispose();
    super.dispose();
  }
}
