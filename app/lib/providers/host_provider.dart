import 'package:flutter/foundation.dart';
import '../models/host.dart';
import '../services/storage_service.dart';

class HostProvider extends ChangeNotifier {
  final StorageService _storage;
  List<Host> _hosts = [];
  String _search = '';

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

  void setSearch(String q) {
    _search = q;
    notifyListeners();
  }

  Future<void> _load() async {
    _hosts = await _storage.loadHosts();
    notifyListeners();
  }

  Future<void> addHost(Host host, {String? password}) async {
    _hosts.add(host);
    await _storage.saveHosts(_hosts);
    if (password != null && password.isNotEmpty) {
      await _storage.savePassword(host.id, password);
    }
    notifyListeners();
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
  }

  Future<void> deleteHost(String id) async {
    _hosts.removeWhere((h) => h.id == id);
    await _storage.saveHosts(_hosts);
    await _storage.deletePassword(id);
    notifyListeners();
  }
}
