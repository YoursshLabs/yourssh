import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../mobile/files/app_paths.dart';
import '../models/ssh_key.dart';
import '../platform/runtime_platform.dart';

class KeyProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.keys';
  List<SshKeyEntry> _keys = [];

  List<SshKeyEntry> get keys => _keys;

  /// Completes once the saved keys are loaded.
  late final Future<void> ready;

  /// Scan `~/.ssh` for default keys on load. Tests pass false so they never
  /// read the real home directory.
  final bool discoverSshKeys;

  /// Resolves the app-owned private keys dir (without creating it). Injectable
  /// for tests.
  final Future<String> Function() _keysDirPath;

  KeyProvider({
    this.discoverSshKeys = true,
    Future<String> Function()? keysDirPath,
  }) : _keysDirPath = keysDirPath ?? AppPaths.privateKeysDirPath {
    ready = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _keys = list
            .map((e) => SshKeyEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint(
          '[KeyProvider] saved keys JSON malformed, starting empty: $e',
        );
        _keys = [];
      }
    }
    if (isIOSPlatform && await _rebaseKeyPaths()) await _save();
    // Auto-discover keys from ~/.ssh
    if (discoverSshKeys) await _discoverSshKeys();
    notifyListeners();
  }

  /// iOS changes the data-container path on reinstall/update, so absolute
  /// paths under `<ApplicationSupport>/keys` saved earlier go stale. Re-anchors
  /// each missing one on the current keys dir. Returns true if any changed.
  Future<bool> _rebaseKeyPaths() async {
    final String dir;
    try {
      dir = await _keysDirPath();
    } catch (e) {
      debugPrint('[KeyProvider] cannot resolve keys dir, skipping rebase: $e');
      return false;
    }
    final marker = '${p.separator}${AppPaths.keysDirName}${p.separator}';
    String? rebase(String? path) {
      if (path == null || File(path).existsSync()) return null;
      final i = path.lastIndexOf(marker);
      if (i < 0) return null;
      final rebased = p.join(dir, path.substring(i + marker.length));
      return File(rebased).existsSync() ? rebased : null;
    }

    var changed = false;
    for (final k in _keys) {
      final key = rebase(k.privateKeyPath);
      if (key != null) {
        k.privateKeyPath = key;
        changed = true;
      }
      final cert = rebase(k.certificatePath);
      if (cert != null) {
        k.certificatePath = cert;
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _discoverSshKeys() async {
    final sshDir = Directory(
      p.join(Platform.environment['HOME'] ?? '', '.ssh'),
    );
    if (!sshDir.existsSync()) return;

    final knownPrivate = {'id_ed25519', 'id_rsa', 'id_ecdsa', 'id_dsa'};
    for (final name in knownPrivate) {
      final keyFile = File(p.join(sshDir.path, name));
      final pubFile = File(p.join(sshDir.path, '$name.pub'));
      if (!keyFile.existsSync()) continue;
      // Skip already registered keys
      if (_keys.any((k) => k.privateKeyPath == keyFile.path)) continue;

      final algo = _algorithmFrom(name);
      final pubKey = pubFile.existsSync()
          ? pubFile.readAsStringSync().trim()
          : '';
      _keys.add(
        SshKeyEntry(
          label: name,
          algorithm: algo,
          publicKey: pubKey,
          privateKeyPath: keyFile.path,
        ),
      );
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

  Future<SshKeyEntry> addKeyFromFile(String path, String label) async {
    final file = File(path);
    if (!file.existsSync()) throw Exception('Key file not found: $path');

    final pubFile = File('$path.pub');
    final pubKey = pubFile.existsSync()
        ? pubFile.readAsStringSync().trim()
        : '';
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
    return entry;
  }

  Future<void> deleteKey(String id) async {
    final removed = findById(id);
    _keys.removeWhere((k) => k.id == id);
    if (removed != null) await _deleteOwnedFiles(removed);
    await _save();
    notifyListeners();
  }

  /// Deletes the key's files only when they live in the app-owned keys dir;
  /// anything elsewhere (e.g. `~/.ssh`) is never touched.
  Future<void> _deleteOwnedFiles(SshKeyEntry k) async {
    final String dir;
    try {
      dir = await _keysDirPath();
    } catch (_) {
      return;
    }
    final path = k.privateKeyPath;
    if (!p.isWithin(dir, path)) return;
    if (_keys.any((o) => o.privateKeyPath == path)) return; // still referenced
    for (final f in [path, '$path.pub', '$path-cert.pub', k.certificatePath]) {
      if (f == null || !p.isWithin(dir, f)) continue;
      try {
        final file = File(f);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        debugPrint('[KeyProvider] could not delete $f: $e');
      }
    }
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
    await prefs.setString(
      _prefsKey,
      jsonEncode(_keys.map((k) => k.toJson()).toList()),
    );
  }

  SshKeyEntry? findById(String id) {
    try {
      return _keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }
}
