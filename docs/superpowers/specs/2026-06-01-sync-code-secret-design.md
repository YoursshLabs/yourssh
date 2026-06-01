# Design: Sync code as the sync secret

Date: 2026-06-01
Status: Approved (brainstorming) — pending implementation plan

## Problem

Cloud sync currently keys every Supabase row by the hardcoded id `'default'`
and encrypts the payload with the **Supabase anon key** (plus an optional
passphrase) as the KDF input. The anon key is public — it ships in the client
and is required to talk to the project — so without a passphrase the encrypted
payload is effectively unprotected against anyone who can read the project.

The committed migration and the `SyncEncryption` layer were already written for
a stronger model: a 12-character random **sync code** that is both the row id
and the KDF secret. `SyncEncryption.encrypt(plaintext, syncId, passphrase:)`
already derives its key from `syncId` (via PBKDF2 + per-row salt). The service
layer never wired it up — it passes the anon key where `syncId` is expected and
keys rows by `'default'`. This spec completes that original design.

## Goal

Make a 12-char sync code the single sync secret: both the Supabase row id and
the encryption KDF input. The anon key becomes purely an API credential. Remove
the passphrase concept.

## Security model

- Confidentiality comes entirely from the sync code. Holding the project URL +
  anon key lets a caller read/write rows, but every payload is AES-256-GCM
  encrypted with a key derived from the sync code (PBKDF2-HMAC-SHA256, 100k
  iterations, per-row random salt — already implemented in `SyncEncryption`).
- The sync code is never stored server-side except as the row id; the row id is
  not a secret on its own because the payload is encrypted under it.
- Anon key alone can no longer decrypt anything.

## Code format

- Alphabet: Crockford Base32 (32 symbols: `0-9A-Z` excluding `I L O U`), which
  removes visually ambiguous characters.
- Length: 12 symbols => ~60 bits of entropy.
- Generation: `Random.secure()`.
- Display: grouped as `XXXX-XXXX-XXXX`. Stored as 12 contiguous chars (no
  separators) so it satisfies the table's `char_length(sync_id) = 12` check.
- New utility `SyncCode`:
  - `generate()` -> 12-char code.
  - `format(code)` -> `XXXX-XXXX-XXXX` for display.
  - `normalize(input)` -> strip separators/whitespace, uppercase.
  - `isValid(input)` -> normalized length == 12 and all chars in alphabet.

## Components

### SyncProvider (`app/lib/providers/sync_provider.dart`)
- Remove `passphrase` / `hasPassphrase` / `_passphraseKey` / `setPassphrase`.
- Add `syncCode` getter, `hasSyncCode`, `setSyncCode(String)`,
  `generateSyncCode()`. Persist the code in secure storage under key
  `sync_code` (same mechanism the passphrase used).
- Keep `isSupabaseConfigured` = url + anonKey (so the user can test the
  Supabase connection before a code exists). Add `enabled` = isSupabaseConfigured
  + a valid syncCode; only `enabled` gates actual push/pull.
- On init / upgrade: delete any stored `sync_passphrase` secret (one-time
  cleanup).
- `clearSupabaseConfig()` also clears the sync code.

### SupabaseService (`app/lib/services/supabase_service.dart`)
- Constructor takes `(url, anonKey, syncCode)`.
- `_rowKey` becomes the injected `syncCode` instead of the const `'default'`.
- Keep the embedded `migrationSql` in sync with the migration file (12-char
  constraint + `with check (char_length(sync_id) = 12)`) — revert the earlier
  "relax to `check(true)`" change.

### SyncService (`app/lib/services/sync_service.dart`)
- Pass `_syncProvider.syncCode` (not the anon key) as the KDF secret to
  `SyncEncryption.encrypt` / `decrypt`. Drop the `passphrase:` argument.
- Construct `SupabaseService(url, anonKey, syncCode)`; extend the
  `_getSupabase()` cache key to include `syncCode` so a code change rebuilds the
  client.
- Push/pull guards: if there is no valid sync code, set a clear error
  ("Generate or enter a sync code in Settings -> Sync") and return.

### Settings UI (`app/lib/widgets/settings_screen.dart`)
- Replace the passphrase field with a Sync code section:
  - No code yet: a "Generate new code" button (this device becomes the source)
    and a "Join with existing code" input.
  - Code set: show the code (masked with a reveal toggle + copy button),
    "Regenerate" (with a warning that it orphans existing remote data because
    the row id changes), and "Remove".
- Update the in-app setup SQL block (already sourced from
  `SupabaseService.migrationSql`) accordingly.

### Schema (`supabase/migrations/20260529000000_sync_data.sql`)
- Revert to the original 12-char form: `sync_id text primary key check
  (char_length(sync_id) = 12)` and policy `with check (char_length(sync_id) =
  12)`. The constraint acts as a guard ensuring only well-formed codes are
  written. Provide the matching setup SQL for users to apply.

## Onboarding / data migration

- Fresh start: no automatic migration of the old `'default'` row. After upgrade,
  sync requires a code; if none is set, status prompts the user to generate or
  enter one. The first push under a code writes a new row keyed by that code.
- Old `'default'` rows are left untouched (harmless orphans the user can delete
  from Supabase if desired).

## Error handling

- Validate a pasted/typed code (`SyncCode.isValid`) before saving; reject
  invalid input in the UI with an inline message.
- A wrong code that passes format validation fails at decrypt time:
  `SyncEncryption.decrypt` already throws `ArgumentError('invalid sync code')`,
  surfaced through `SyncProvider.setError`.

## Testing

- `SyncCode` unit tests: generated length/alphabet; `normalize` handles
  dashes/whitespace/lowercase; `isValid` rejects wrong length and out-of-alphabet
  chars.
- `SyncEncryption`: round-trip encrypt/decrypt keyed by a sync code; decrypt with
  a different code fails (most coverage already exists).
- `SyncService`: push writes a row keyed by the sync code and encrypted with it;
  pull decrypts with the same code; missing code short-circuits with an error.
- `SyncProvider`: `setSyncCode` / `generateSyncCode` persist and gate `enabled`;
  `clearSupabaseConfig` wipes the code; upgrade path deletes the old passphrase
  secret.

## Out of scope (YAGNI)

- Sharing the code through the existing QR / P2P flow.
- Multiple sync groups / multiple rows per project.
- Automatic re-encryption migration from the old `'default'` row.
