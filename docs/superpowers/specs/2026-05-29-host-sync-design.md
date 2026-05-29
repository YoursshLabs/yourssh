# Host Sync Across Devices — Design Spec

**Date:** 2026-05-29  
**Status:** Approved  

---

## Goal

Allow a user to sync their SSH host list (including passwords) across multiple macOS/Windows devices automatically, with zero configuration beyond entering a 12-character sync code on each additional device.

---

## Architecture

Five new components are added to the existing provider/service layer:

| Component | File | Responsibility |
|---|---|---|
| `SyncEncryption` | `app/lib/services/sync_encryption.dart` | AES-256-GCM encrypt/decrypt payload |
| `SupabaseService` | `app/lib/services/supabase_service.dart` | Thin wrapper: init Supabase client, read/write sync row |
| `SyncService` | `app/lib/services/sync_service.dart` | Orchestrate push/pull, retry queue, focus listener |
| `SyncProvider` | `app/lib/providers/sync_provider.dart` | ChangeNotifier — sync state (enabled, syncing, error, lastSynced) |
| Sync UI | `app/lib/widgets/settings_screen.dart` (modified) | Sync section with code display, pairing input, status |

**No new screens.** Sync lives entirely inside the existing `SettingsScreen`.

---

## Data Model

### Supabase Table

```sql
CREATE TABLE sync_data (
  sync_id    TEXT PRIMARY KEY,
  payload    TEXT        NOT NULL,  -- AES-256-GCM encrypted JSON (base64)
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS: open read/write — security via encrypted payload + secret sync_id
ALTER TABLE sync_data ENABLE ROW LEVEL SECURITY;
CREATE POLICY "open" ON sync_data FOR ALL USING (true) WITH CHECK (true);
```

### Encrypted Payload Schema

```json
{
  "hosts": [ { ...Host.toJson()... } ],
  "passwords": { "pw_<hostId>": "<plaintext_password>", ... },
  "updated_at": "2026-05-29T10:00:00.000Z"
}
```

### sync_id & Sync Code

- `sync_id` **is** the sync code — a random 12-character string (chars: `A-Z`, `2-9`, no `0/1/O/I` for readability), formatted as `XXXX-XXXX-XXXX` (e.g., `X7KD-M2PQ-3RVA`)
- Generated once on first use, stored in `FlutterSecureStorage` under key `sync_id`
- Serves dual purpose: **Supabase primary key** (lookup) + **encryption key seed**
- ~58 bits of entropy — brute-force infeasible given Supabase rate limiting + encrypted payload

### Encryption

- **Key derivation:** `PBKDF2(password: sync_id, salt: "yourssh-sync-v1", iterations: 100000, keyLength: 32, hash: SHA-256)`
- **Cipher:** AES-256-GCM
- **IV:** 12 random bytes, generated fresh per encrypt
- **Stored format:** `base64(iv[12] + ciphertext + authTag[16])`
- **Wrong key:** GCM auth tag mismatch → throws `ArgumentError("invalid sync code")`

---

## Sync Flow

### First Launch

1. Check `FlutterSecureStorage` for `sync_id`
2. If absent → generate UUID v4, write to SecureStorage
3. Sync is **disabled by default** — user must enable in Settings

### Enable Sync (Device 1)

1. User toggles "Enable Sync" ON in Settings
2. `SyncProvider` sets `enabled = true`, persists to `SharedPreferences`
3. App derives `sync_code` from `sync_id`, displays it
4. `SyncService.push()` runs immediately — encrypts and upserts to Supabase

### Pair Device 2

1. User toggles "Enable Sync" ON → taps "I have a code from another device"
2. Enters 12-char sync code (dashes optional, case-insensitive)
3. App derives `sync_id` from code → writes to SecureStorage (replaces any existing)
4. `SyncService.pull()` runs → fetches + decrypts → replaces local host list
5. From this point on, sync behaves identically to Device 1

### Ongoing Auto Sync

- **Push:** called by `HostProvider` after every `addHost`, `updateHost`, `deleteHost`  
- **Pull:** called at app startup and whenever the app window regains focus (`WindowManager.onWindowFocus`)
- **Conflict resolution:** last-write-wins on `updated_at`. If `remote.updated_at > local_last_push_at` → pull wins (replace local). Otherwise → push wins (skip pull).

### Offline Handling

- Push failure → set `hasPendingPush = true` in `SharedPreferences`
- `SyncService` has a 30-second periodic timer that retries if `hasPendingPush == true`
- Pull failure → show error status, retry on next focus event

### Disable Sync

1. User toggles OFF
2. `SyncProvider` sets `enabled = false`
3. `SupabaseService.deleteSyncRow(sync_id)` — removes remote data
4. Local data untouched

---

## UI

### Settings Screen — Sync Section

```
SYNC
────────────────────────────────────────
Enable Sync                  [Switch]

[When ON:]

Sync Code
┌──────────────┐
│  X7KD-M2PQ  │  [Copy]
└──────────────┘
Enter this code on other devices to sync.

Status:  ● Synced · 2 minutes ago
         ⟳ Syncing…
         ✕ Sync error · [Retry]

──── Connect to another device ────
┌──────────────────────────────┐
│  Enter sync code…            │
└──────────────────────────────┘
[Connect]
```

### Hosts Dashboard Header

Small icon appended to header row (right side):
- `⟳` (spinning) while syncing
- `✓` when last sync succeeded
- `⚠` when sync error

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| No internet on push | Set `hasPendingPush = true`, retry every 30s |
| Supabase unreachable | Log, set `SyncStatus.error`, show in UI, do not crash |
| Invalid sync code entered | Decrypt fails → show "Invalid sync code, please check and try again" |
| Two devices push simultaneously | Last push wins — `updated_at` determines winner on next pull |
| User disables sync | Delete remote row, keep local data |

---

## Testing

- **`SyncEncryption` unit tests:** encrypt→decrypt roundtrip; wrong key throws; IV uniqueness (two encrypts of same plaintext produce different output)
- **`SyncService` unit tests:** push serialises correctly; pull with newer remote replaces local; pull with older remote is skipped; pending retry logic
- **Widget tests:** sync toggle on/off; code display; error state render; pairing input validation

---

## Out of Scope (v1)

- Syncing SSH key files (keychain entries) — only host list + passwords
- Per-host conflict resolution / merge history
- Team/multi-user sharing
- Sync audit log
- End-to-end push notifications (realtime Supabase subscriptions)
