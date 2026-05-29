import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class VaultEntry {
  final String id;
  final String label;
  final String username;
  final String password;
  final String notes;
  final DateTime createdAt;

  VaultEntry({
    String? id,
    required this.label,
    required this.username,
    required this.password,
    this.notes = '',
  })  : id = id ?? const Uuid().v4(),
        createdAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'username': username,
        'password': password,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        label: json['label'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
        notes: json['notes'] as String? ?? '',
      );
}

class VaultService {
  static const _storageKey = 'vault_entries_v1';
  final _storage = const FlutterSecureStorage();

  Future<List<VaultEntry>> loadAll() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(VaultEntry.fromJson).toList();
  }

  Future<void> save(List<VaultEntry> entries) async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(VaultEntry entry) async {
    final entries = await loadAll();
    entries.add(entry);
    await save(entries);
  }

  Future<void> delete(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.id == id);
    await save(entries);
  }

  Future<void> update(VaultEntry updated) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) entries[idx] = updated;
    await save(entries);
  }
}
