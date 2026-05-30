import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncStatus { idle, syncing, synced, error }

class SyncProvider extends ChangeNotifier {
  static const _supabaseUrlKey = 'supabase_url';
  static const _supabaseAnonKeyKey = 'supabase_anon_key';

  SyncStatus _status = SyncStatus.idle;
  String? _error;
  DateTime? _lastSynced;
  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  bool _supabaseConfigExplicitlySet = false;
  bool _disposed = false;

  bool get enabled => isSupabaseConfigured;
  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSynced => _lastSynced;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;
  bool get isSupabaseConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

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
    if (!_supabaseConfigExplicitlySet) {
      _supabaseUrl = prefs.getString(_supabaseUrlKey) ?? '';
      _supabaseAnonKey = prefs.getString(_supabaseAnonKeyKey) ?? '';
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

  Future<void> clearSupabaseConfig() async {
    _supabaseUrl = '';
    _supabaseAnonKey = '';
    _supabaseConfigExplicitlySet = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_supabaseUrlKey);
    await prefs.remove(_supabaseAnonKeyKey);
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
