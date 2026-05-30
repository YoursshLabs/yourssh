# Runtime Supabase Configuration — Design Spec

**Date:** 2026-05-29  
**Status:** Approved

## Problem

Currently `SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected at build time (`--dart-define`), meaning:
- The developer must know the Supabase credentials before building
- End-users cannot configure their own backend
- CI/CD must keep credentials as build secrets

## Goal

Users enter the Project URL + anon key directly in the Settings UI. The app saves them to `SharedPreferences` and initializes `SupabaseClient` at runtime — no dart-define needed, no rebuild required.

## Architecture

### Data flow

```
Settings UI
  └── SyncProvider.setSupabaseConfig(url, key)
        └── SharedPreferences (save url, anon_key)
              └── SyncService._getSupabase()
                    └── SupabaseClient(url, key)  ← lazy init, cached
```

### Component changes

**`SyncProvider`** — add 2 fields:
- `String _supabaseUrl`, `String _supabaseAnonKey` — loaded from `SharedPreferences` in `_init()`
- `bool get isSupabaseConfigured`
- `Future<void> setSupabaseConfig(url, anonKey)` — save + notifyListeners

**`SupabaseService`** — fully refactored:
- Remove `static const` dart-define, remove `Supabase.initialize()` singleton
- Constructor `SupabaseService(String url, String anonKey)` — creates `SupabaseClient` directly
- `String get url`, `String get anonKey` — for SyncService to detect credential changes
- `Future<(bool, String?)> testConnection()` — validate credentials + table existence

**`SyncService`** — replace constructor param:
- Remove `SupabaseService` from constructor: `SyncService(this._syncProvider)`
- Add `SupabaseService? _getSupabase()` — lazy create, cache, invalidate when credentials change
- push/pull/disableAndDelete guard: if `_getSupabase() == null` → setError with a clear message

**`main.dart`**:
- Remove `await SupabaseService.initialize()`
- Change constructor: `SyncService(_syncProvider)` (no longer takes `SupabaseService()`)

**Settings UI** — add Supabase config section in `_SyncSection`:
- 2 text fields: Project URL, Anon Key (with show/hide toggle)
- "Save & Test" button → calls `testConnection()` → displays result
- "Enable Sync" toggle disabled when not yet configured

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
| Table `sync_data` does not exist | `(false, 'Table "sync_data" not found. Run SQL migration.')` |
| OK | `(true, null)` |

## Error handling

- When Supabase is not configured and user enables Enable Sync → `SyncStatus.error` with a guidance message
- `testConnection()` wrapped in try-catch, returns tuple `(bool, String?)` instead of throwing
- `SupabaseClient` creation in try-catch (invalid URL format)

## Files changed

1. `app/lib/providers/sync_provider.dart`
2. `app/lib/services/supabase_service.dart`
3. `app/lib/services/sync_service.dart`
4. `app/lib/main.dart`
5. `app/lib/widgets/settings_screen.dart`
6. `docs/SYNC_SETUP.md`

## Out of scope

- Re-initializing Supabase when credentials change mid-session (cached client will swap on the next operation)
- Auto-running migrations from the app
- Multiple Supabase backends
