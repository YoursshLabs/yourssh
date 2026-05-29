import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host.dart';
import '../providers/sync_provider.dart';
import '../services/supabase_service.dart';
import '../services/sync_encryption.dart';

class SyncPayload {
  final List<Host> hosts;
  final Map<String, String> passwords;
  final DateTime updatedAt;
  SyncPayload({required this.hosts, required this.passwords, required this.updatedAt});
}

class SyncService {
  static const _lastPushKey = 'sync_last_push_at';
  static const _pendingPushKey = 'sync_pending_push';

  final SyncProvider _syncProvider;
  final SupabaseService _supabase;
  Timer? _retryTimer;
  Future<List<Host>> Function()? _getHosts;
  Future<Map<String, String>> Function()? _loadPasswords;
  bool _syncing = false;

  SyncService(this._syncProvider, this._supabase);

  // ── Static helpers (testable without instance) ────────────

  static String buildPayload({
    required List<Host> hosts,
    required Map<String, String> passwords,
  }) {
    return jsonEncode({
      'hosts': hosts.map((h) => h.toJson()).toList(),
      'passwords': passwords,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static SyncPayload parsePayload(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final hosts = (map['hosts'] as List)
        .map((e) => Host.fromJson(e as Map<String, dynamic>))
        .toList();
    final passwords = (map['passwords'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
    return SyncPayload(
      hosts: hosts,
      passwords: passwords,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  static bool shouldPullRemote(DateTime remoteUpdatedAt, DateTime? lastPushAt) {
    if (lastPushAt == null) return true; // new device: always pull remote
    return remoteUpdatedAt.isAfter(lastPushAt);
  }

  // ── Push ──────────────────────────────────────────────────

  Future<void> push({
    required List<Host> hosts,
    required Future<Map<String, String>> Function() loadPasswords,
  }) async {
    if (!_syncProvider.enabled) return;
    if (_syncProvider.syncId.isEmpty) return;
    if (_syncing) return;
    _syncing = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      _syncProvider.setStatus(SyncStatus.syncing);
      final passwords = await loadPasswords();
      final payload = buildPayload(hosts: hosts, passwords: passwords);
      final encrypted = await SyncEncryption.encrypt(payload, _syncProvider.syncId);
      await _supabase.upsertPayload(_syncProvider.syncId, encrypted);
      await prefs.setString(_lastPushKey, DateTime.now().toUtc().toIso8601String());
      await prefs.setBool(_pendingPushKey, false);
      _syncing = false;
      _syncProvider.setStatus(SyncStatus.synced);
    } catch (e) {
      _syncing = false;
      await prefs.setBool(_pendingPushKey, true);
      _syncProvider.setError(e.toString());
    }
  }

  // ── Pull ──────────────────────────────────────────────────

  Future<SyncPayload?> pull() async {
    if (!_syncProvider.enabled) return null;
    if (_syncProvider.syncId.isEmpty) return null;
    if (_syncing) return null;
    _syncing = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      _syncProvider.setStatus(SyncStatus.syncing);
      final lastPushStr = prefs.getString(_lastPushKey);
      final lastPushAt = lastPushStr != null ? DateTime.parse(lastPushStr) : null;

      final remoteUpdatedAt = await _supabase.fetchUpdatedAt(_syncProvider.syncId);
      if (remoteUpdatedAt == null) {
        _syncing = false;
        _syncProvider.setStatus(SyncStatus.synced);
        return null;
      }
      if (!shouldPullRemote(remoteUpdatedAt, lastPushAt)) {
        _syncing = false;
        _syncProvider.setStatus(SyncStatus.synced);
        return null;
      }
      final encrypted = await _supabase.fetchPayload(_syncProvider.syncId);
      if (encrypted == null) {
        _syncing = false;
        _syncProvider.setStatus(SyncStatus.synced);
        return null;
      }
      final decrypted = await SyncEncryption.decrypt(encrypted, _syncProvider.syncId);
      final result = parsePayload(decrypted);
      await prefs.setBool(_pendingPushKey, false);
      _syncing = false;
      _syncProvider.setStatus(SyncStatus.synced);
      return result;
    } catch (e) {
      _syncing = false;
      _syncProvider.setError(e.toString());
      return null;
    }
  }

  // ── Retry timer ───────────────────────────────────────────

  void startRetryTimer({
    required Future<List<Host>> Function() getHosts,
    required Future<Map<String, String>> Function() loadPasswords,
  }) {
    _getHosts = getHosts;
    _loadPasswords = loadPasswords;
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool(_pendingPushKey) ?? false;
      if (pending && _getHosts != null && _loadPasswords != null) {
        final hosts = await _getHosts!();
        await push(hosts: hosts, loadPasswords: _loadPasswords!);
      }
    });
  }

  void restartRetryTimer() {
    if (_getHosts != null && _loadPasswords != null) {
      startRetryTimer(getHosts: _getHosts!, loadPasswords: _loadPasswords!);
    }
  }

  void stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ── Disable ───────────────────────────────────────────────

  Future<void> disableAndDelete() async {
    stopRetryTimer();
    await _supabase.deleteSyncRow(_syncProvider.syncId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingPushKey);
    await prefs.remove(_lastPushKey);
    await _syncProvider.setEnabled(false);
  }

  void dispose() {
    stopRetryTimer();
  }
}
