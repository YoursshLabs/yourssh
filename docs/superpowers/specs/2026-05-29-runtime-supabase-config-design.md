# Runtime Supabase Configuration — Design Spec

**Date:** 2026-05-29  
**Status:** Approved

## Problem

Hiện tại `SUPABASE_URL` và `SUPABASE_ANON_KEY` được inject lúc build (`--dart-define`), nghĩa là:
- Developer phải biết Supabase credentials trước khi build
- End-user không thể tự cấu hình backend của mình
- CI/CD phải giữ credentials dưới dạng build secrets

## Goal

User điền Project URL + anon key trực tiếp trong Settings UI. App lưu vào `SharedPreferences` và khởi tạo `SupabaseClient` tại runtime — không cần dart-define, không cần rebuild.

## Architecture

### Data flow

```
Settings UI
  └── SyncProvider.setSupabaseConfig(url, key)
        └── SharedPreferences (lưu url, anon_key)
              └── SyncService._getSupabase()
                    └── SupabaseClient(url, key)  ← lazy init, cached
```

### Component changes

**`SyncProvider`** — thêm 2 field:
- `String _supabaseUrl`, `String _supabaseAnonKey` — load từ `SharedPreferences` trong `_init()`
- `bool get isSupabaseConfigured`
- `Future<void> setSupabaseConfig(url, anonKey)` — save + notifyListeners

**`SupabaseService`** — refactor hoàn toàn:
- Bỏ `static const` dart-define, bỏ `Supabase.initialize()` singleton
- Constructor `SupabaseService(String url, String anonKey)` — tạo `SupabaseClient` trực tiếp
- `String get url`, `String get anonKey` — để SyncService detect credential change
- `Future<(bool, String?)> testConnection()` — validate credentials + table existence

**`SyncService`** — thay thế constructor param:
- Bỏ `SupabaseService` khỏi constructor: `SyncService(this._syncProvider)`
- Thêm `SupabaseService? _getSupabase()` — lazy create, cache, invalidate khi credentials đổi
- push/pull/disableAndDelete guard: nếu `_getSupabase() == null` → setError với message rõ ràng

**`main.dart`**:
- Bỏ `await SupabaseService.initialize()`
- Đổi constructor: `SyncService(_syncProvider)` (không còn `SupabaseService()`)

**Settings UI** — thêm Supabase config section trong `_SyncSection`:
- 2 text fields: Project URL, Anon Key (với toggle show/hide)
- Nút "Save & Test" → gọi `testConnection()` → hiển thị kết quả
- Toggle "Enable Sync" disabled khi chưa configured

### UX layout (Settings → Sync section)

```
SYNC
┌─────────────────────────────────────────────┐
│ SUPABASE                                     │
│  Project URL  [https://xxx.supabase.co    ] │
│  Anon Key     [***********************    ] │
│                                 [Save & Test]│
│  ✓ Connected  / ✗ <error message>            │
├─────────────────────────────────────────────│
│ Enable Sync                        [toggle] │  ← disabled if not configured
│ ...existing sync code / connect UI...       │
└─────────────────────────────────────────────┘
```

### `testConnection()` behavior

| Scenario | Result |
|---|---|
| Credentials invalid / wrong URL | `(false, "Invalid API key / URL")` |
| Table `sync_data` không tồn tại | `(false, 'Table "sync_data" not found. Run SQL migration.')` |
| OK | `(true, null)` |

## Error handling

- Khi Supabase chưa configured và user bật Enable Sync → `SyncStatus.error` với message hướng dẫn
- `testConnection()` wrapped trong try-catch, trả về tuple `(bool, String?)` thay vì throw
- `SupabaseClient` creation trong try-catch (URL format invalid)

## Files changed

1. `app/lib/providers/sync_provider.dart`
2. `app/lib/services/supabase_service.dart`
3. `app/lib/services/sync_service.dart`
4. `app/lib/main.dart`
5. `app/lib/widgets/settings_screen.dart`
6. `docs/SYNC_SETUP.md`

## Out of scope

- Re-init Supabase khi credentials đổi trong mid-session (cached client sẽ tự swap ở lần op tiếp theo)
- Migration auto-run từ app
- Multiple Supabase backends
