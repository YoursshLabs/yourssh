import 'package:shared_preferences/shared_preferences.dart';
import '../js_runtime_registrar.dart';

class MigrationBridge {
  static const _oldKey = 'yourssh.snippets';

  void register(JsRuntimeRegistrar rt) {
    rt.registerHostFn('_migration', 'readOldSnippets', _read);
    rt.registerHostFn('_migration', 'clearOldSnippets', _clear);
  }

  String? _read(String _) {
    final prefs = _cachedPrefs;
    if (prefs == null) return null;
    return prefs.getString(_oldKey);
  }

  String? _clear(String _) {
    _cachedPrefs?.remove(_oldKey);
    return null;
  }

  static SharedPreferences? _cachedPrefs;

  static Future<void> warmup() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
  }
}
