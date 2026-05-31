import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ssh_key.dart';

class KeyProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.keys';
  List<SshKeyEntry> _keys = [];

  List<SshKeyEntry> get keys => _keys;

  KeyProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _keys = list.map((e) => SshKeyEntry.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('[KeyProvider] saved keys JSON malformed, starting empty: $e');
        _keys = [];
      }
    }
    // Auto-discover keys from ~/.ssh
    await _discoverSshKeys();
    notifyListeners();
  }

  Future<void> _discoverSshKeys() async {
    final sshDir = Directory(p.join(Platform.environment['HOME'] ?? '', '.ssh'));
    if (!sshDir.existsSync()) return;

    final knownPrivate = {'id_ed25519', 'id_rsa', 'id_ecdsa', 'id_dsa'};
    for (final name in knownPrivate) {
      final keyFile = File(p.join(sshDir.path, name));
      final pubFile = File(p.join(sshDir.path, '$name.pub'));
      if (!keyFile.existsSync()) continue;
      // Skip already registered keys
      if (_keys.any((k) => k.privateKeyPath == keyFile.path)) continue;

      final algo = _algorithmFrom(name);
      final pubKey = pubFile.existsSync() ? pubFile.readAsStringSync().trim() : '';
      _keys.add(SshKeyEntry(
        label: name,
        algorithm: algo,
        publicKey: pubKey,
        privateKeyPath: keyFile.path,
      ));
      final certFile = File(p.join(sshDir.path, '$name-cert.pub'));
      if (certFile.existsSync()) {
        _keys.last.certificatePath = certFile.path;
      }
    }
    await _save();
  }

  /// Infers the key algorithm from a filename or path by substring match.
  KeyAlgorithm _algorithmFrom(String nameOrPath) {
    if (nameOrPath.contains('ed25519')) return KeyAlgorithm.ed25519;
    if (nameOrPath.contains('ecdsa')) return KeyAlgorithm.ecdsa;
    return KeyAlgorithm.rsa;
  }

  Future<void> addKeyFromFile(String path, String label) async {
    final file = File(path);
    if (!file.existsSync()) throw Exception('Key file not found: $path');

    final pubFile = File('$path.pub');
    final pubKey = pubFile.existsSync() ? pubFile.readAsStringSync().trim() : '';
    final algo = _algorithmFrom(path);

    final entry = SshKeyEntry(
      label: label,
      algorithm: algo,
      publicKey: pubKey,
      privateKeyPath: path,
    );
    _keys.add(entry);
    final certFile = File('$path-cert.pub');
    if (certFile.existsSync()) {
      _keys.last.certificatePath = certFile.path;
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteKey(String id) async {
    _keys.removeWhere((k) => k.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> setCertificate(String keyId, String certPath) async {
    final idx = _keys.indexWhere((k) => k.id == keyId);
    if (idx == -1) return;
    _keys[idx].certificatePath = certPath;
    await _save();
    notifyListeners();
  }

  Future<void> removeCertificate(String keyId) async {
    final idx = _keys.indexWhere((k) => k.id == keyId);
    if (idx == -1) return;
    _keys[idx].certificatePath = null;
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_keys.map((k) => k.toJson()).toList()));
  }

  SshKeyEntry? findById(String id) {
    try {
      return _keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }
}
