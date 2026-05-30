import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/command_history.dart';

class CommandHistoryProvider extends ChangeNotifier {
  static const _prefKey = 'command_history_v1';
  static const _maxPerSession = 500;
  static const _persistDebounce = Duration(milliseconds: 500);

  final Map<String, CommandHistory> _histories = {};
  Timer? _persistTimer;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    // Flush any pending changes synchronously-ish so a quick app close still
    // saves the last command.
    if (_persistTimer != null) unawaited(_persist());
    super.dispose();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        _histories[entry.key] = CommandHistory.fromJson(
          entry.value as Map<String, dynamic>,
          maxSize: _maxPerSession,
        );
      }
    } catch (e) {
      debugPrint('[CommandHistoryProvider] history JSON malformed, ignoring: $e');
    }
  }

  CommandHistory historyFor(String sessionId) =>
      _histories.putIfAbsent(sessionId, () => CommandHistory(maxSize: _maxPerSession));

  void recordCommand(String sessionId, String command) {
    historyFor(sessionId).add(command);
    _schedulePersist();
    notifyListeners();
  }

  String? navigateUp(String sessionId) => historyFor(sessionId).navigateUp();
  String? navigateDown(String sessionId) => historyFor(sessionId).navigateDown();
  void resetCursor(String sessionId) => historyFor(sessionId).resetCursor();

  List<String> suggestions(String sessionId, String prefix) {
    if (prefix.isEmpty) return [];
    return historyFor(sessionId)
        .entries
        .where((e) => e.startsWith(prefix))
        .take(8)
        .toList();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      if (_disposed) return;
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {for (final e in _histories.entries) e.key: e.value.toJson()};
    await prefs.setString(_prefKey, jsonEncode(map));
  }
}
