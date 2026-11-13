import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ssh_key.dart';

class KeyProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.keys';
  static const _dismissedKey = 'yourssh.keys.dismissed';
  List<SshKeyEntry> _keys = [];

  List<SshKeyEntry> get keys => _keys;

  /// Completes once the saved keys are loaded.
  late final Future<void> ready;

  /// Scan `~/.ssh` for default keys on load. Tests pass false so they never
  /// read the real home directory.
  final bool discoverSshKeys;

  /// Directory scanned by auto-discovery; defaults to `~/.ssh`. Tests inject a
  /// temp dir.
  final String? sshDirPath;

  KeyProvider({this.discoverSshKeys = true, this.sshDirPath}) {
    ready = _load();
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
    if (discoverSshKeys) await _discoverSshKeys();
    notifyListeners();
  }

  Future<void> _discoverSshKeys() async {
    final sshDir = Directory(
        sshDirPath ?? p.join(Platform.environment['HOME'] ?? '', '.ssh'));
    if (!sshDir.existsSync()) return;
    final dismissed = await _loadDismissed();

    final knownPrivate = {'id_ed25519', 'id_rsa', 'id_ecdsa', 'id_dsa'};
    for (final name in knownPrivate) {
      final keyFile = File(p.join(sshDir.path, name));
      final pubFile = File(p.join(sshDir.path, '$name.pub'));
      if (!keyFile.existsSync()) continue;
      // Skip already registered keys
      if (_keys.any((k) => k.privateKeyPath == keyFile.path)) continue;
      // Skip keys the user removed earlier
      if (dismissed.contains(keyFile.path)) continue;

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

  /// Persists key passphrases (wired to StorageService.savePassphrase in
  /// main.dart — StorageService is not in the provider tree).
  Future<void> Function(String keyId, String passphrase)? savePassphrase;

  /// Deletes a key's stored passphrase (wired to
  /// StorageService.deletePassphrase in main.dart / mobile bootstrap).
  Future<void> Function(String keyId)? deletePassphrase;

  Future<Set<String>> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_dismissedKey) ?? const []).toSet();
  }

  Future<void> _saveDismissed(Set<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    if (paths.isEmpty) {
      await prefs.remove(_dismissedKey);
    } else {
      await prefs.setStringList(_dismissedKey, paths.toList());
    }
  }

  Future<SshKeyEntry> addKeyFromFile(String path, String label) async {
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
    // Explicit re-import clears an earlier dismissal of this path.
    final dismissed = await _loadDismissed();
    if (dismissed.remove(path)) await _saveDismissed(dismissed);
    final certFile = File('$path-cert.pub');
    if (certFile.existsSync()) {
      _keys.last.certificatePath = certFile.path;
    }
    await _save();
    notifyListeners();
    return entry;
  }

  Future<void> deleteKey(String id) async {
    final removed = findById(id);
    _keys.removeWhere((k) => k.id == id);
    await _save();
    // Remember the path so auto-discovery doesn't re-add it next launch.
    final path = removed?.privateKeyPath;
    if (path != null && path.isNotEmpty) {
      final dismissed = await _loadDismissed();
      if (dismissed.add(path)) await _saveDismissed(dismissed);
    }
    try {
      await deletePassphrase?.call(id);
    } catch (e) {
      debugPrint('[KeyProvider] failed to delete passphrase for $id: $e');
    }
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
