import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host.dart';

class StorageService {
  static const _hostsKey = 'yourssh.hosts';
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(accountName: 'yourssh'),
    wOptions: WindowsOptions(),
  );

  // ── Hosts ──────────────────────────────────────────────

  Future<List<Host>> loadHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Host.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveHosts(List<Host> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostsKey, jsonEncode(hosts.map((h) => h.toJson()).toList()));
  }

  // ── Credentials (Keychain / Credential Manager) ────────

  Future<void> savePassword(String hostId, String password) async {
    await _storage.write(key: 'pw_$hostId', value: password);
  }

  Future<String?> loadPassword(String hostId) async {
    return _storage.read(key: 'pw_$hostId');
  }

  Future<void> deletePassword(String hostId) async {
    await _storage.delete(key: 'pw_$hostId');
  }

  Future<void> savePassphrase(String keyId, String passphrase) async {
    await _storage.write(key: 'pp_$keyId', value: passphrase);
  }

  Future<String?> loadPassphrase(String keyId) async {
    return _storage.read(key: 'pp_$keyId');
  }
}
