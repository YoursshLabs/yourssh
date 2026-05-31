import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/terminal_layout_provider.dart';

class WorkspaceSnapshot {
  final List<String> hostIds;
  final String? activeHostId;
  final SplitLayout layout;
  final bool inputBarVisible;

  const WorkspaceSnapshot({
    required this.hostIds,
    required this.activeHostId,
    required this.layout,
    required this.inputBarVisible,
  });

  Map<String, dynamic> toJson() => {
        'hostIds': hostIds,
        'activeHostId': activeHostId,
        'layout': layout.name,
        'inputBarVisible': inputBarVisible,
      };

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) =>
      WorkspaceSnapshot(
        hostIds: List<String>.from(json['hostIds'] as List),
        activeHostId: json['activeHostId'] as String?,
        layout: SplitLayout.values.firstWhere(
          (e) => e.name == json['layout'],
          orElse: () => SplitLayout.single,
        ),
        inputBarVisible: (json['inputBarVisible'] as bool?) ?? false,
      );
}

class WorkspaceService {
  static const _key = 'workspace_snapshot';

  Future<void> save(WorkspaceSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<WorkspaceSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return WorkspaceSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WorkspaceService] malformed snapshot, ignoring: $e');
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
