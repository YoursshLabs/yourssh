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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(hostId),
      jsonEncode({'label': label, 'color': color, 'pinned': pinned}),
    );
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(hostId));
  }
}
