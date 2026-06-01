import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';
import '../services/sync_code.dart';

enum SyncStatus { idle, syncing, synced, error }

class SyncProvider extends ChangeNotifier {
  static const _supabaseUrlKey = 'supabase_url';
  static const _supabaseAnonKeyKey = 'supabase_anon_key';
  static const _syncCodeKey = 'sync_code';
  static const _legacyPassphraseKey = 'sync_passphrase';

  final StorageService? _storage;

  SyncStatus _status = SyncStatus.idle;
  String? _error;
  DateTime? _lastSynced;
  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  String _syncCode = '';
  bool _supabaseConfigExplicitlySet = false;
  bool _disposed = false;

  bool get enabled => isSupabaseConfigured && hasSyncCode;
  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSynced => _lastSynced;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;

  /// The 12-char sync code: the single secret for cloud sync (row id + KDF
  /// input). Empty until the user generates one or joins with an existing code.
  String get syncCode => _syncCode;
  bool get hasSyncCode => _syncCode.length == SyncCode.length;

  bool get isSupabaseConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  // ignore: prefer_initializing_formals
  SyncProvider({StorageService? storage}) : _storage = storage {
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
    if (!_supabaseConfigExplicitlySet) {
      _supabaseUrl = prefs.getString(_supabaseUrlKey) ?? '';
      _supabaseAnonKey = prefs.getString(_supabaseAnonKeyKey) ?? '';
    }
    if (_storage != null) {
      _syncCode = await _storage.loadGenericSecret(_syncCodeKey) ?? '';
      // One-time cleanup of the abandoned passphrase secret.
      await _storage.deleteGenericSecret(_legacyPassphraseKey);
    }
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> setSupabaseConfig(String url, String anonKey) async {
    _supabaseUrl = url.trim();
    _supabaseAnonKey = anonKey.trim();
    _supabaseConfigExplicitlySet = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_supabaseUrlKey, _supabaseUrl);
    await prefs.setString(_supabaseAnonKeyKey, _supabaseAnonKey);
  }

  Future<void> setSyncCode(String value) async {
    final normalized = SyncCode.normalize(value);
    if (_storage != null) {
      if (normalized.isEmpty) {
        await _storage.deleteGenericSecret(_syncCodeKey);
      } else {
        await _storage.saveGenericSecret(_syncCodeKey, normalized);
      }
    }
    _syncCode = normalized;
    notifyListeners();
  }

  Future<String> generateSyncCode() async {
    final code = SyncCode.generate();
    await setSyncCode(code);
    return code;
  }

  Future<void> clearSupabaseConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_supabaseUrlKey);
    await prefs.remove(_supabaseAnonKeyKey);
    if (_storage != null) {
      await _storage.deleteGenericSecret(_syncCodeKey);
    }
    _supabaseUrl = '';
    _supabaseAnonKey = '';
    _syncCode = '';
    _supabaseConfigExplicitlySet = false;
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
