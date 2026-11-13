import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/snippet.dart';

const _kNativeKey = 'yourssh.snippets';
const _kJsKey = 'plugin::dev.yourssh.snippets::storage::snippets';
const _kRecoveredKey = 'yourssh.snippets.js_recovered';

/// Earlier builds bundled a script copy of Snippets that moved the native
/// `yourssh.snippets` prefs into its own storage and deleted the original.
/// Copy those snippets back: restore when the native key is missing, otherwise
/// append the entries (by label + command) it lacks. The JS copy is never
/// deleted, malformed data is ignored, and it runs once so a snippet the user
/// deletes later is not brought back.
Future<void> recoverJsSnippets(SharedPreferences prefs) async {
  if (prefs.getBool(_kRecoveredKey) == true) return;
  final jsRaw = prefs.getString(_kJsKey);
  if (jsRaw == null) return;
  final List<Map<String, dynamic>> js;
  try {
    final decoded = jsonDecode(jsRaw);
    if (decoded is! List) return;
    js = [
      for (final e in decoded)
        if (e is Map && e['label'] is String && e['command'] is String)
          Map<String, dynamic>.from(e)
    ];
  } catch (_) {
    return;
  }
  if (js.isEmpty) return;

  final nativeRaw = prefs.getString(_kNativeKey);
  List<dynamic> merged;
  if (nativeRaw == null) {
    merged = js;
  } else {
    try {
      final decoded = jsonDecode(nativeRaw);
      if (decoded is! List) return;
      merged = [...decoded];
    } catch (_) {
      return;
    }
    final seen = {
      for (final e in merged)
        if (e is Map) '${e['label']}\u0000${e['command']}'
    };
    for (final e in js) {
      if (seen.add('${e['label']}\u0000${e['command']}')) merged.add(e);
    }
  }
  await prefs.setString(_kNativeKey, jsonEncode(merged));
  await prefs.setBool(_kRecoveredKey, true);
}

class SnippetProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.snippets';
  final List<Snippet> _snippets = [];

  List<Snippet> get snippets => _snippets;

  SnippetProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await recoverJsSnippets(prefs);
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _snippets.addAll(list.map((e) => Snippet.fromJson(e as Map<String, dynamic>)));
    } else {
      _loadDefaults();
    }
    notifyListeners();
  }

  void _loadDefaults() {
    _snippets.addAll([
      Snippet(label: 'Disk usage', command: 'df -h', description: 'Show disk space', tag: 'system'),
      Snippet(label: 'Memory info', command: 'free -m', description: 'Show memory usage', tag: 'system'),
      Snippet(label: 'Running processes', command: 'ps aux', description: 'List all processes', tag: 'system'),
      Snippet(label: 'Tail syslog', command: 'tail -f /var/log/syslog', description: 'Follow system log', tag: 'logs'),
      Snippet(label: 'Network interfaces', command: 'ip addr show', description: 'List network interfaces', tag: 'network'),
      Snippet(label: 'Open ports', command: 'ss -tlnp', description: 'Show listening ports', tag: 'network'),
    ]);
    _save();
  }

  Future<void> add(Snippet snippet) async {
    _snippets.add(snippet);
    await _save();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _snippets.removeWhere((s) => s.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_snippets.map((s) => s.toJson()).toList()));
  }
}
