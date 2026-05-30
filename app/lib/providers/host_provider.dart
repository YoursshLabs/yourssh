import 'package:flutter/foundation.dart';
import '../models/host.dart';
import '../services/storage_service.dart';

class HostProvider extends ChangeNotifier {
  final StorageService _storage;
  List<Host> _hosts = [];
  List<String> _pinnedGroups = [];
  String _search = '';

  /// Called after any mutation so SyncService can push.
  Future<void> Function()? onMutation;

  HostProvider(this._storage) {
    _load();
  }

  List<Host> get hosts => _search.isEmpty
      ? _hosts
      : _hosts
          .where((h) =>
              h.label.toLowerCase().contains(_search.toLowerCase()) ||
              h.host.toLowerCase().contains(_search.toLowerCase()))
          .toList();

  List<Host> get allHosts => _hosts;

  List<String> get pinnedGroups => List.unmodifiable(_pinnedGroups);

  Future<void> addGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final alreadyExists = _pinnedGroups.any(
      (g) => g.toLowerCase() == trimmed.toLowerCase(),
    );
    if (alreadyExists) return;
    _pinnedGroups.add(trimmed);
    await _storage.savePinnedGroups(_pinnedGroups);
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> removeGroup(String name) async {
    _pinnedGroups.removeWhere((g) => g.toLowerCase() == name.toLowerCase());
    await _storage.savePinnedGroups(_pinnedGroups);
    notifyListeners();
    await onMutation?.call();
  }

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  Future<void> _load() async {
    _hosts = await _storage.loadHosts();
    _pinnedGroups = await _storage.loadPinnedGroups();
    notifyListeners();
  }

  Future<void> addHost(Host host, {String? password}) async {
    _hosts.add(host);
    await _storage.saveHosts(_hosts);
    if (password != null && password.isNotEmpty) {
      await _storage.savePassword(host.id, password);
    }
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> updateHost(Host host, {String? password}) async {
    final idx = _hosts.indexWhere((h) => h.id == host.id);
    if (idx == -1) return;
    _hosts[idx] = host;
    await _storage.saveHosts(_hosts);
    if (password != null && password.isNotEmpty) {
      await _storage.savePassword(host.id, password);
    }
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> deleteHost(String id) async {
    _hosts.removeWhere((h) => h.id == id);
    await _storage.saveHosts(_hosts);
    await _storage.deletePassword(id);
    notifyListeners();
    await onMutation?.call();
  }

  Future<void> replaceAll(List<Host> hosts, Map<String, String> passwords) async {
    final oldIds = _hosts.map((h) => h.id).toSet();
    final newIds = hosts.map((h) => h.id).toSet();
    final removedIds = oldIds.difference(newIds);
    _hosts = hosts;
    await _storage.saveHosts(_hosts);
    for (final id in removedIds) {
      await _storage.deletePassword(id);
    }
    for (final entry in passwords.entries) {
      final hostId = entry.key.replaceFirst('pw_', '');
      await _storage.savePassword(hostId, entry.value);
    }
    notifyListeners();
  }

  Future<Map<String, String>> loadAllPasswords() async {
    final result = <String, String>{};
    for (final host in _hosts) {
      final pw = await _storage.loadPassword(host.id);
      if (pw != null) result['pw_${host.id}'] = pw;
    }
    return result;
  }
}
