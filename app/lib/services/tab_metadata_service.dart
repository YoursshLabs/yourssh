import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TabMetadataService {
  static String _key(String hostId) => 'tab_meta_$hostId';

  Future<void> saveMetadata(
    String hostId, {
    required String? label,
    required String? color,
    required bool pinned,
  }) async {
    // Callers fire-and-forget this write, so a failure would otherwise be
    // swallowed silently — log it instead of dropping it without a trace.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(hostId),
        jsonEncode({'label': label, 'color': color, 'pinned': pinned}),
      );
    } catch (e) {
      debugPrint('[TabMetadataService] failed to save metadata for $hostId: $e');
    }
  }

  Future<Map<String, dynamic>?> loadMetadata(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(hostId));
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[TabMetadataService] malformed metadata for $hostId: $e');
      return null;
    }
  }

  Future<void> clearMetadata(String hostId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(hostId));
    } catch (e) {
      debugPrint('[TabMetadataService] failed to clear metadata for $hostId: $e');
    }
  }
}
