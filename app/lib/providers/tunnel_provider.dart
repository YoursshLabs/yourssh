import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tunnel_config.dart';

class TunnelProvider extends ChangeNotifier {
  static const _prefKey = 'tunnels_v1';
  final List<TunnelConfig> _tunnels = [];

  List<TunnelConfig> get tunnels => List.unmodifiable(_tunnels);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _tunnels.addAll(list.map(TunnelConfig.fromJson));
    } catch (e) {
      debugPrint('[TunnelProvider] tunnels JSON malformed, starting empty: $e');
    }
    notifyListeners();
  }

  void add(TunnelConfig tunnel) {
    _tunnels.add(tunnel);
    _persist();
    notifyListeners();
  }

  void remove(String id) {
    _tunnels.removeWhere((t) => t.id == id);
    _persist();
    notifyListeners();
  }

  void updateStatus(String id, TunnelStatus status, {String? url, String? error}) {
    final idx = _tunnels.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _tunnels[idx].status = status;
    if (url != null) _tunnels[idx].publicUrl = url;
    if (error != null) _tunnels[idx].errorMessage = error;
    notifyListeners();
  }

  void resetToIdle(String id) {
    final idx = _tunnels.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _tunnels[idx].status = TunnelStatus.idle;
    _tunnels[idx].publicUrl = null;
    _tunnels[idx].errorMessage = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode(_tunnels.map((t) => t.toJson()).toList()),
    );
  }
}
