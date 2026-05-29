import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/snippet.dart';

class SnippetProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.snippets';
  final List<Snippet> _snippets = [];

  List<Snippet> get snippets => _snippets;

  SnippetProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
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
