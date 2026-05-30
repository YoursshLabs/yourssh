import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';

enum SyncStatus { idle, syncing, synced, error }

class SyncProvider extends ChangeNotifier {
  static const _supabaseUrlKey = 'supabase_url';
  static const _supabaseAnonKeyKey = 'supabase_anon_key';
  static const _passphraseKey = 'sync_passphrase';

  final StorageService? _storage;

  SyncStatus _status = SyncStatus.idle;
  String? _error;
  DateTime? _lastSynced;
  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  String _passphrase = '';
  bool _supabaseConfigExplicitlySet = false;
  bool _disposed = false;

  bool get enabled => isSupabaseConfigured;
  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSynced => _lastSynced;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;

  /// User-supplied passphrase mixed into the sync encryption KDF. Empty means
  /// the anon key alone is the secret (legacy behaviour) — anyone with that
  /// key can decrypt synced rows. Setting a passphrase is recommended.
  String get passphrase => _passphrase;
  bool get hasPassphrase => _passphrase.isNotEmpty;

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
      _passphrase = await _storage.loadGenericSecret(_passphraseKey) ?? '';
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

  Future<void> setPassphrase(String value) async {
    if (_storage != null) {
      if (value.isEmpty) {
        await _storage.deleteGenericSecret(_passphraseKey);
      } else {
        await _storage.saveGenericSecret(_passphraseKey, value);
      }
    }
    _passphrase = value;
    notifyListeners();
  }

  Future<void> clearSupabaseConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_supabaseUrlKey);
    await prefs.remove(_supabaseAnonKeyKey);
    if (_storage != null) {
      await _storage.deleteGenericSecret(_passphraseKey);
    }
    _supabaseUrl = '';
    _supabaseAnonKey = '';
    _passphrase = '';
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
