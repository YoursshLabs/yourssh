import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncStatus { idle, syncing, synced, error }

class SyncProvider extends ChangeNotifier {
  static const _syncIdKey = 'sync_id';
  static const _enabledKey = 'sync_enabled';
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(accountName: 'yourssh'),
    wOptions: WindowsOptions(),
  );
  static const _charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  bool _enabled = false;
  SyncStatus _status = SyncStatus.idle;
  String? _error;
  DateTime? _lastSynced;
  String _syncId = '';
  bool _disposed = false;

  bool get enabled => _enabled;
  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSynced => _lastSynced;
  String get syncId => _syncId;

  set syncId(String value) {
    _syncId = value;
    notifyListeners();
  }

  String get syncCodeDisplay {
    if (_syncId.length < 12) return _syncId;
    return '${_syncId.substring(0, 4)}-${_syncId.substring(4, 8)}-${_syncId.substring(8, 12)}';
  }

  SyncProvider() {
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _enabled = prefs.getBool(_enabledKey) ?? false;
    String? stored = await _storage.read(key: _syncIdKey);
    if (_disposed) return;
    if (stored == null || stored.isEmpty) {
      stored = _generateSyncId();
      await _storage.write(key: _syncIdKey, value: stored);
    }
    if (_disposed) return;
    _syncId = stored;
    notifyListeners();
  }

  String _generateSyncId() {
    final rng = Random.secure();
    return List.generate(12, (_) => _charset[rng.nextInt(_charset.length)]).join();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> replaceSyncId(String rawCode) async {
    final clean = rawCode.replaceAll('-', '').toUpperCase();
    _syncId = clean;
    await _storage.write(key: _syncIdKey, value: clean);
    notifyListeners();
  }

  void setStatus(SyncStatus status) {
    _status = status;
    if (status == SyncStatus.synced) {
      _error = null;
      _lastSynced = DateTime.now();
    }
    notifyListeners();
  }

  void setError(String message) {
    _status = SyncStatus.error;
    _error = message;
    notifyListeners();
  }
}
