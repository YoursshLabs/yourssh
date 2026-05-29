# Runtime Supabase Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** User điền Supabase Project URL + anon key trong Settings UI; app lưu vào SharedPreferences và khởi tạo `SupabaseClient` tại runtime — không cần `--dart-define` hay rebuild.

**Architecture:** `SupabaseService` được refactor thành instance class nhận `(url, anonKey)` qua constructor, dùng `SupabaseClient` trực tiếp thay vì `Supabase.initialize()` singleton. `SyncService` lazy-create `SupabaseService` từ credentials trong `SyncProvider`. Settings UI thêm config section với Save & Test.

**Tech Stack:** Flutter, provider, supabase_flutter (`SupabaseClient` direct), shared_preferences, flutter_test

---

## File Map

| File | Action | Mô tả |
|---|---|---|
| `app/lib/services/supabase_service.dart` | Rewrite | Runtime constructor, `testConnection()`, bỏ singleton |
| `app/lib/providers/sync_provider.dart` | Modify | Thêm `supabaseUrl`/`supabaseAnonKey` + `setSupabaseConfig()` |
| `app/lib/services/sync_service.dart` | Modify | Bỏ `SupabaseService` khỏi constructor, thêm `_getSupabase()` lazy init |
| `app/lib/main.dart` | Modify | Bỏ `SupabaseService.initialize()`, đơn giản hóa constructor |
| `app/lib/widgets/settings_screen.dart` | Modify | Thêm Supabase config section trong `_SyncSection` |
| `docs/SYNC_SETUP.md` | Rewrite | Hướng dẫn runtime thay vì dart-define |
| `app/test/supabase_service_test.dart` | Create | Unit test cho SupabaseService constructor/getters |
| `app/test/sync_provider_supabase_test.dart` | Create | Unit test cho SyncProvider Supabase config |

---

### Task 1: Rewrite SupabaseService

**Files:**
- Modify: `app/lib/services/supabase_service.dart`
- Create: `app/test/supabase_service_test.dart`

- [x] **Step 1: Write the failing test**

```dart
// app/test/supabase_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/supabase_service.dart';

void main() {
  test('stores url and anonKey via constructor', () {
    final svc = SupabaseService('https://abc.supabase.co', 'anon-key-123');
    expect(svc.url, 'https://abc.supabase.co');
    expect(svc.anonKey, 'anon-key-123');
  });
}
```

- [x] **Step 2: Run to confirm it fails**

```bash
cd app && flutter test test/supabase_service_test.dart
```

Expected: compile error — `SupabaseService` không nhận constructor params và không có `url`/`anonKey` getters.

- [x] **Step 3: Rewrite `supabase_service.dart`**

Thay toàn bộ nội dung file:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final String _url;
  final String _anonKey;
  late final SupabaseClient _client;

  SupabaseService(this._url, this._anonKey) {
    _client = SupabaseClient(_url, _anonKey);
  }

  String get url => _url;
  String get anonKey => _anonKey;

  /// Returns (true, null) on success; (false, errorMessage) on failure.
  Future<(bool, String?)> testConnection() async {
    try {
      await _client.from('sync_data').select('sync_id').limit(1);
      return (true, null);
    } on PostgrestException catch (e) {
      if (e.code == '42P01') {
        return (false, 'Table "sync_data" not found. Run the SQL migration (see docs/SYNC_SETUP.md).');
      }
      return (false, e.message);
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<String?> fetchPayload(String syncId) async {
    final response = await _client
        .from('sync_data')
        .select('payload')
        .eq('sync_id', syncId)
        .maybeSingle();
    return response?['payload'] as String?;
  }

  Future<DateTime?> fetchUpdatedAt(String syncId) async {
    final response = await _client
        .from('sync_data')
        .select('updated_at')
        .eq('sync_id', syncId)
        .maybeSingle();
    if (response == null) return null;
    return DateTime.parse(response['updated_at'] as String);
  }

  Future<void> upsertPayload(String syncId, String payload) async {
    await _client.from('sync_data').upsert({
      'sync_id': syncId,
      'payload': payload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> deleteSyncRow(String syncId) async {
    await _client.from('sync_data').delete().eq('sync_id', syncId);
  }
}
```

- [x] **Step 4: Run test**

```bash
cd app && flutter test test/supabase_service_test.dart
```

Expected: PASS

- [x] **Step 5: Commit**

```bash
git add app/lib/services/supabase_service.dart app/test/supabase_service_test.dart
git commit -m "refactor: SupabaseService runtime constructor, drop Supabase.initialize singleton"
```

---

### Task 2: Extend SyncProvider with Supabase config

**Files:**
- Modify: `app/lib/providers/sync_provider.dart`
- Create: `app/test/sync_provider_supabase_test.dart`

- [x] **Step 1: Write the failing tests**

```dart
// app/test/sync_provider_supabase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/sync_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('isSupabaseConfigured is false on fresh provider', () {
    final p = SyncProvider();
    expect(p.isSupabaseConfigured, isFalse);
    expect(p.supabaseUrl, '');
    expect(p.supabaseAnonKey, '');
  });

  test('setSupabaseConfig updates getters and persists', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('https://x.supabase.co', 'anon-key-abc');
    expect(p.supabaseUrl, 'https://x.supabase.co');
    expect(p.supabaseAnonKey, 'anon-key-abc');
    expect(p.isSupabaseConfigured, isTrue);

    // Verify persisted to prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('supabase_url'), 'https://x.supabase.co');
    expect(prefs.getString('supabase_anon_key'), 'anon-key-abc');
  });

  test('setSupabaseConfig trims whitespace', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('  https://x.supabase.co  ', '  key  ');
    expect(p.supabaseUrl, 'https://x.supabase.co');
    expect(p.supabaseAnonKey, 'key');
  });

  test('isSupabaseConfigured false when only URL is set', () async {
    final p = SyncProvider();
    await p.setSupabaseConfig('https://x.supabase.co', '');
    expect(p.isSupabaseConfigured, isFalse);
  });
}
```

- [x] **Step 2: Run to confirm it fails**

```bash
cd app && flutter test test/sync_provider_supabase_test.dart
```

Expected: compile error — `supabaseUrl`, `supabaseAnonKey`, `isSupabaseConfigured`, `setSupabaseConfig` không tồn tại.

- [x] **Step 3: Add constants to `sync_provider.dart`**

Sau `static const _enabledKey = 'sync_enabled';` thêm:

```dart
static const _supabaseUrlKey = 'supabase_url';
static const _supabaseAnonKeyKey = 'supabase_anon_key';
```

- [x] **Step 4: Add fields**

Sau `String _syncId = '';` thêm:

```dart
String _supabaseUrl = '';
String _supabaseAnonKey = '';
```

- [x] **Step 5: Add getters**

Sau `String get syncId => _syncId;` thêm:

```dart
String get supabaseUrl => _supabaseUrl;
String get supabaseAnonKey => _supabaseAnonKey;
bool get isSupabaseConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
```

- [x] **Step 6: Add `setSupabaseConfig` method**

Sau `Future<void> setEnabled(bool value)` thêm:

```dart
Future<void> setSupabaseConfig(String url, String anonKey) async {
  _supabaseUrl = url.trim();
  _supabaseAnonKey = anonKey.trim();
  notifyListeners();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_supabaseUrlKey, _supabaseUrl);
  await prefs.setString(_supabaseAnonKeyKey, _supabaseAnonKey);
}
```

- [x] **Step 7: Load from prefs in `_init()`**

Trong `_init()`, sau dòng `_enabled = prefs.getBool(_enabledKey) ?? false;` thêm:

```dart
_supabaseUrl = prefs.getString(_supabaseUrlKey) ?? '';
_supabaseAnonKey = prefs.getString(_supabaseAnonKeyKey) ?? '';
```

- [x] **Step 8: Run tests**

```bash
cd app && flutter test test/sync_provider_supabase_test.dart
```

Expected: PASS

- [x] **Step 9: Commit**

```bash
git add app/lib/providers/sync_provider.dart app/test/sync_provider_supabase_test.dart
git commit -m "feat: add Supabase runtime config to SyncProvider"
```

---

### Task 3: Refactor SyncService

**Files:**
- Modify: `app/lib/services/sync_service.dart`

- [x] **Step 1: Replace constructor và `_supabase` field**

Tìm:
```dart
final SyncProvider _syncProvider;
final SupabaseService _supabase;
Timer? _retryTimer;
// ...
SyncService(this._syncProvider, this._supabase);
```

Thay bằng:
```dart
final SyncProvider _syncProvider;
SupabaseService? _cachedSupabase;
Timer? _retryTimer;
// ...
SyncService(this._syncProvider);

SupabaseService? _getSupabase() {
  if (!_syncProvider.isSupabaseConfigured) return null;
  final url = _syncProvider.supabaseUrl;
  final key = _syncProvider.supabaseAnonKey;
  if (_cachedSupabase == null ||
      _cachedSupabase!.url != url ||
      _cachedSupabase!.anonKey != key) {
    _cachedSupabase = SupabaseService(url, key);
  }
  return _cachedSupabase;
}
```

- [x] **Step 2: Rewrite `push()`**

```dart
Future<void> push({
  required List<Host> hosts,
  required Future<Map<String, String>> Function() loadPasswords,
}) async {
  if (!_syncProvider.enabled) return;
  if (_syncProvider.syncId.isEmpty) return;
  if (_syncing) return;
  final supabase = _getSupabase();
  if (supabase == null) {
    _syncProvider.setError('Supabase not configured. Enter your project URL and anon key in Settings → Sync.');
    return;
  }
  _syncing = true;
  final prefs = await SharedPreferences.getInstance();
  try {
    _syncProvider.setStatus(SyncStatus.syncing);
    final passwords = await loadPasswords();
    final payload = buildPayload(hosts: hosts, passwords: passwords);
    final encrypted = await SyncEncryption.encrypt(payload, _syncProvider.syncId);
    await supabase.upsertPayload(_syncProvider.syncId, encrypted);
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
```

- [x] **Step 3: Rewrite `pull()`**

```dart
Future<SyncPayload?> pull() async {
  if (!_syncProvider.enabled) return null;
  if (_syncProvider.syncId.isEmpty) return null;
  if (_syncing) return null;
  final supabase = _getSupabase();
  if (supabase == null) {
    _syncProvider.setError('Supabase not configured. Enter your project URL and anon key in Settings → Sync.');
    return null;
  }
  _syncing = true;
  final prefs = await SharedPreferences.getInstance();
  try {
    _syncProvider.setStatus(SyncStatus.syncing);
    final lastPushStr = prefs.getString(_lastPushKey);
    final lastPushAt = lastPushStr != null ? DateTime.parse(lastPushStr) : null;
    final remoteUpdatedAt = await supabase.fetchUpdatedAt(_syncProvider.syncId);
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
    final encrypted = await supabase.fetchPayload(_syncProvider.syncId);
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
```

- [x] **Step 4: Update `disableAndDelete()`**

```dart
Future<void> disableAndDelete() async {
  stopRetryTimer();
  try {
    final supabase = _getSupabase();
    if (supabase != null) {
      await supabase.deleteSyncRow(_syncProvider.syncId);
    }
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_pendingPushKey);
  await prefs.remove(_lastPushKey);
  await _syncProvider.setEnabled(false);
}
```

- [x] **Step 5: Verify compile**

```bash
cd app && flutter analyze lib/services/sync_service.dart
```

Expected: no errors

- [x] **Step 6: Commit**

```bash
git add app/lib/services/sync_service.dart
git commit -m "refactor: SyncService lazy-creates SupabaseService from SyncProvider credentials"
```

---

### Task 4: Update main.dart

**Files:**
- Modify: `app/lib/main.dart`

- [x] **Step 1: Remove `SupabaseService` import và initialize call**

Xóa dòng import:
```dart
import 'services/supabase_service.dart';
```

Đổi `main()` từ:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(800, 600));
  await SupabaseService.initialize();
  runApp(const YourSSHApp());
}
```

Thành:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(800, 600));
  runApp(const YourSSHApp());
}
```

- [x] **Step 2: Update SyncService constructor trong `initState()`**

Đổi:
```dart
_syncService = SyncService(_syncProvider, SupabaseService());
```

Thành:
```dart
_syncService = SyncService(_syncProvider);
```

- [x] **Step 3: Verify compile**

```bash
cd app && flutter analyze lib/main.dart
```

Expected: no errors

- [x] **Step 4: Commit**

```bash
git add app/lib/main.dart
git commit -m "refactor: remove SupabaseService.initialize, no longer needed at startup"
```

---

### Task 5: Update Settings UI

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

- [x] **Step 1: Add import cho `SupabaseService`**

Sau dòng `import '../services/storage_service.dart';` thêm:

```dart
import '../services/supabase_service.dart';
```

- [x] **Step 2: Thêm fields và `initState` vào `_SyncSectionState`**

Thêm vào đầu class (sau `final _codeController`):

```dart
final _urlController = TextEditingController();
final _anonKeyController = TextEditingController();
bool _showAnonKey = false;
bool _testing = false;
bool _testOk = false;
String? _testError;
```

Thêm `initState()` (trước `dispose()`):

```dart
@override
void initState() {
  super.initState();
  _urlController.text = widget.sync.supabaseUrl;
  _anonKeyController.text = widget.sync.supabaseAnonKey;
  if (widget.sync.isSupabaseConfigured) _testOk = true;
}
```

Cập nhật `dispose()`:

```dart
@override
void dispose() {
  _codeController.dispose();
  _urlController.dispose();
  _anonKeyController.dispose();
  super.dispose();
}
```

- [x] **Step 3: Thêm `_testAndSave()` method**

Thêm sau `_connect()`:

```dart
Future<void> _testAndSave() async {
  final url = _urlController.text.trim();
  final anonKey = _anonKeyController.text.trim();
  if (url.isEmpty || anonKey.isEmpty) {
    setState(() { _testError = 'URL and anon key are required'; _testOk = false; });
    return;
  }
  setState(() { _testing = true; _testError = null; });
  try {
    await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
    if (!mounted) return;
    final (ok, error) = await SupabaseService(url, anonKey).testConnection();
    if (!mounted) return;
    setState(() { _testing = false; _testOk = ok; _testError = ok ? null : error; });
  } catch (e) {
    if (!mounted) return;
    setState(() { _testing = false; _testOk = false; _testError = e.toString(); });
  }
}
```

- [x] **Step 4: Cập nhật `_onToggle()` — guard khi chưa config**

```dart
Future<void> _onToggle(bool value) async {
  final sync = context.read<SyncProvider>();
  if (!sync.isSupabaseConfigured) return;
  final syncService = context.read<SyncService>();
  if (!value) {
    await syncService.disableAndDelete();
  } else {
    await sync.setEnabled(true);
    if (!mounted) return;
    final hostProvider = context.read<HostProvider>();
    final storage = context.read<StorageService>();
    final passwords = <String, String>{};
    for (final host in hostProvider.allHosts) {
      final pw = await storage.loadPassword(host.id);
      if (pw != null) passwords['pw_${host.id}'] = pw;
    }
    await syncService.push(
      hosts: hostProvider.allHosts,
      loadPasswords: () async => passwords,
    );
    syncService.restartRetryTimer();
  }
}
```

- [x] **Step 5: Thêm `_buildTestStatus()` helper**

Thêm sau `_testAndSave()`:

```dart
Widget _buildTestStatus() {
  if (_testing) return const SizedBox.shrink();
  if (_testOk) {
    return const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.check_circle, size: 12, color: Colors.green),
      SizedBox(width: 4),
      Text('Connected', style: TextStyle(color: Colors.green, fontSize: 11)),
    ]);
  }
  if (_testError != null) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 12, color: Colors.red),
      const SizedBox(width: 4),
      Flexible(child: Text(_testError!, style: const TextStyle(color: Colors.red, fontSize: 11), overflow: TextOverflow.ellipsis)),
    ]);
  }
  return const SizedBox.shrink();
}
```

- [x] **Step 6: Thay toàn bộ `build()` của `_SyncSectionState`**

```dart
@override
Widget build(BuildContext context) {
  final sync = widget.sync;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('SYNC', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // ── Supabase backend config ──────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Supabase Backend', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Project URL',
                      labelStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      hintText: 'https://xxxx.supabase.co',
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.bg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _anonKeyController,
                    obscureText: !_showAnonKey,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Anon Key',
                      labelStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      hintText: 'eyJhbGciOiJIUzI1NiIs...',
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.bg,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                      suffixIcon: IconButton(
                        icon: Icon(_showAnonKey ? Icons.visibility_off : Icons.visibility, size: 16, color: AppColors.textTertiary),
                        onPressed: () => setState(() => _showAnonKey = !_showAnonKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildTestStatus()),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _testing ? null : _testAndSave,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: _testing
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save & Test', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border, indent: 16),
            // ── Enable Sync toggle ───────────────────────────
            SwitchListTile(
              title: const Text('Enable Sync', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              subtitle: Text(
                sync.isSupabaseConfigured
                    ? 'Sync hosts across devices'
                    : 'Configure Supabase above first',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              value: sync.enabled,
              onChanged: sync.isSupabaseConfigured ? _onToggle : null,
            ),
            if (sync.enabled) ...[
              const Divider(height: 1, color: AppColors.border, indent: 16),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sync Code', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(sync.syncCodeDisplay, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontFamily: 'monospace', letterSpacing: 2)),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: sync.syncCodeDisplay));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Sync code copied'), duration: Duration(seconds: 2)),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Enter this code on other devices to sync.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(height: 12),
                    _SyncStatusRow(sync: sync),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 16),
                    const Text('Connect to another device', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Enter sync code…',
                              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                              filled: true,
                              fillColor: AppColors.bg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _connecting ? null : _connect,
                          child: _connecting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Connect', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (_connectError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_connectError!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
```

- [x] **Step 7: Verify compile**

```bash
cd app && flutter analyze lib/widgets/settings_screen.dart
```

Expected: no errors

- [x] **Step 8: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat: add Supabase runtime config UI in Settings → Sync"
```

---

### Task 6: Update SYNC_SETUP.md

**Files:**
- Modify: `docs/SYNC_SETUP.md`

- [x] **Step 1: Rewrite nội dung**

Thay toàn bộ `docs/SYNC_SETUP.md` bằng:

```markdown
# Sync Setup Guide

YourSSH sync dùng Supabase làm backend lưu trữ. Dữ liệu được mã hoá AES-GCM ngay trên client — Supabase chỉ thấy ciphertext.

**Không cần build lại app hay cấu hình dart-define.** Điền credentials trực tiếp trong app.

## 1. Tạo Supabase project

1. Vào [supabase.com](https://supabase.com) → **New project**
2. Chọn region gần nhất (Singapore hoặc Tokyo cho SEA)
3. Đặt database password mạnh → **Create project**

## 2. Chạy migration tạo bảng

### Cách A — Supabase Dashboard (dễ nhất)

1. Vào **SQL Editor** trong dashboard
2. Copy nội dung file `supabase/migrations/20260529000000_sync_data.sql`
3. Paste → **Run**

### Cách B — Supabase CLI

```bash
brew install supabase/tap/supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

## 3. Lấy credentials

Vào **Project Settings → API**:

- **Project URL**: `https://<project-ref>.supabase.co`
- **anon public** key: chuỗi JWT dài bên dưới "Project API keys"

## 4. Cấu hình trong app

**Settings → Sync → Supabase Backend:**

1. Điền **Project URL**
2. Điền **Anon Key**
3. Nhấn **Save & Test**
4. Nếu thấy **"Connected"** → bật **Enable Sync**

## 5. Kết nối thiết bị khác

1. **Thiết bị A** (có sẵn data):
   - Settings → Sync → copy **Sync Code** (ví dụ: `ABCD-EFGH-JKLM`)

2. **Thiết bị B** (mới):
   - Settings → Sync → điền **cùng Supabase credentials** → Save & Test
   - Paste sync code vào ô **Enter sync code…** → **Connect**
   - App pull và thay thế toàn bộ danh sách hosts

> **Lưu ý:** Cả hai thiết bị phải dùng cùng Supabase project. Sync code là encryption key — không chia sẻ qua kênh không bảo mật.

## Troubleshooting

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| `Table "sync_data" not found` | Migration chưa chạy | Chạy SQL migration (Bước 2) |
| `Invalid API key` | Anon key sai | Kiểm tra lại Project Settings → API |
| `Invalid sync code` | Code sai hoặc khác project | Đảm bảo nhập đúng 12 ký tự |
```

- [x] **Step 2: Commit**

```bash
git add docs/SYNC_SETUP.md
git commit -m "docs: update SYNC_SETUP for runtime configuration (no dart-define needed)"
```

---

### Task 7: Full verification

- [x] **Step 1: Run all tests**

```bash
cd app && flutter test
```

Expected: PASS — không có failures

- [x] **Step 2: Analyze toàn bộ project**

```bash
cd app && flutter analyze
```

Expected: no errors

- [x] **Step 3: Build check**

```bash
cd app && flutter build macos
```

Expected: build thành công, không cần `--dart-define`
