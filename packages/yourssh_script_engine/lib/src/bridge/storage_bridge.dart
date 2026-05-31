import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Minimal interface StorageBridge needs from a JS runtime.
// QuickJsRuntime (Task 3) will implement this.
abstract class JsRuntimeRegistrar {
  void registerHostFn(
    String bridgeName,
    String fnName,
    String? Function(String arg) handler,
  );
}

class StorageBridge {
  final String _pluginId;

  StorageBridge(this._pluginId);

  void register(JsRuntimeRegistrar rt) {
    rt.registerHostFn('_storage', 'get', _get);
    rt.registerHostFn('_storage', 'set', _set);
    rt.registerHostFn('_storage', 'delete', _delete);
  }

  String _key(String key) => 'plugin::$_pluginId::storage::$key';

  String? _get(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    final key = arg['key'] as String;
    final prefs = _cachedPrefs;
    if (prefs == null) return null;
    final val = prefs.getString(_key(key));
    return val != null ? json.encode({'value': val}) : 'null';
  }

  String? _set(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _cachedPrefs?.setString(_key(arg['key'] as String), arg['value'] as String);
    return null;
  }

  String? _delete(String argJson) {
    final arg = json.decode(argJson) as Map<String, dynamic>;
    _cachedPrefs?.remove(_key(arg['key'] as String));
    return null;
  }

  static SharedPreferences? _cachedPrefs;

  static Future<void> warmup() async {
    _cachedPrefs = await SharedPreferences.getInstance();
  }
}
