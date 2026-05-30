import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/port_forward.dart';

class PortForwardProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.port_forwards';
  final List<PortForward> _forwards = [];

  List<PortForward> get forwards => List.unmodifiable(_forwards);

  PortForwardProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _forwards.addAll(list.map((e) => PortForward.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('[PortForwardProvider] JSON malformed, starting empty: $e');
      }
    }
    notifyListeners();
  }

  Future<void> add(PortForward fwd) async {
    _forwards.add(fwd);
    await _save();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _forwards.removeWhere((f) => f.id == id);
    await _save();
    notifyListeners();
  }

  void setStatus(String id, ForwardStatus status, {String? error}) {
    // Forward may have been deleted between status events (e.g., during
    // teardown) — silently drop the update instead of throwing StateError.
    final fwd = _forwards.where((f) => f.id == id).firstOrNull;
    if (fwd == null) return;
    fwd.status = status;
    fwd.errorMessage = error;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_forwards.map((f) => f.toJson()).toList()));
  }
}
