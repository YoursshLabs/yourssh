# Sync Code As Secret — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a 12-char Crockford-Base32 sync code the single sync secret — both the Supabase row id and the AES-GCM KDF input — and remove the anon-key-as-secret / passphrase model.

**Architecture:** The `SyncEncryption` layer already derives its key from its `syncId` argument; we wire the sync code into it instead of the anon key, key Supabase rows by the code instead of `'default'`, and add a `SyncCode` utility + Settings UX to generate/enter the code.

**Tech Stack:** Flutter, `provider`, `cryptography` (AES-GCM/PBKDF2), `flutter_secure_storage`, `supabase_flutter`.

---

### Task 0: Reset working tree to the 12-char base

**Files:**
- Revert: `app/lib/services/supabase_service.dart`, `supabase/migrations/20260529000000_sync_data.sql` (undo the earlier "relax to check(true)" Option-A edits)
- Commit: `README.md` (screenshot rows already added)

- [ ] **Step 1:** `git checkout -- app/lib/services/supabase_service.dart supabase/migrations/20260529000000_sync_data.sql`
- [ ] **Step 2:** Verify the migration is back to the 12-char form: `grep -n "char_length" supabase/migrations/20260529000000_sync_data.sql` → expect two matches (column check + policy with-check).
- [ ] **Step 3:** Commit the README screenshots: `git add README.md && git commit -m "docs: add P2P QR sync and session recording screenshots to README"`

---

### Task 1: `SyncCode` utility

**Files:**
- Create: `app/lib/services/sync_code.dart`
- Test: `app/test/services/sync_code_test.dart`

- [ ] **Step 1: Write the failing test** (`app/test/services/sync_code_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sync_code.dart';

void main() {
  group('SyncCode', () {
    test('generate produces 12 chars from the Crockford alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = SyncCode.generate();
        expect(code.length, 12);
        expect(code.split('').every(SyncCode.alphabet.contains), isTrue);
      }
    });

    test('generate is random across calls', () {
      final a = SyncCode.generate();
      final b = SyncCode.generate();
      expect(a, isNot(b));
    });

    test('normalize strips separators, uppercases, maps ambiguous chars', () {
      expect(SyncCode.normalize('xxxx-xxxx-xxxx'.replaceAll('x', 'a')),
          'AAAAAAAAAAAA');
      expect(SyncCode.normalize('il o'), '1100'.substring(0, 0) + '11 0'.replaceAll(' ', ''));
    });

    test('normalize maps I/L to 1 and O to 0', () {
      expect(SyncCode.normalize('ILO'), '110');
    });

    test('isValid accepts a generated code and formatted variants', () {
      final code = SyncCode.generate();
      expect(SyncCode.isValid(code), isTrue);
      expect(SyncCode.isValid(SyncCode.format(code)), isTrue);
      expect(SyncCode.isValid(code.toLowerCase()), isTrue);
    });

    test('isValid rejects wrong length and bad chars', () {
      expect(SyncCode.isValid('ABC'), isFalse);
      expect(SyncCode.isValid('AAAAAAAAAAAAA'), isFalse); // 13
      expect(SyncCode.isValid('!@#\$%^&*()_+='), isFalse);
    });

    test('format groups a 12-char code as XXXX-XXXX-XXXX', () {
      expect(SyncCode.format('ABCD2345EFGH'), 'ABCD-2345-EFGH');
    });
  });
}
```

- [ ] **Step 2: Run test, expect FAIL** — `flutter test test/services/sync_code_test.dart` (target import not found).

- [ ] **Step 3: Implement** (`app/lib/services/sync_code.dart`)

```dart
import 'dart:math';

/// A 12-character sync code — the single secret for cloud sync. It is both the
/// Supabase row id (`sync_id`) and the KDF input for payload encryption. Uses
/// the Crockford Base32 alphabet (excludes the ambiguous I, L, O, U) so codes
/// transcribe cleanly by hand.
class SyncCode {
  SyncCode._();

  /// Crockford Base32: digits 0-9 and A-Z minus I, L, O, U. 32 symbols.
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const length = 12;
  static final _rng = Random.secure();

  /// A fresh random 12-char code (~60 bits of entropy).
  static String generate() {
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(alphabet[_rng.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }

  /// Upper-cases, strips separators/whitespace, and maps the Crockford-ambiguous
  /// input characters (I, L -> 1; O -> 0) so a hand-typed code still validates.
  static String normalize(String input) {
    return input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-]'), '')
        .replaceAll(RegExp('[IL]'), '1')
        .replaceAll('O', '0');
  }

  /// True when [input] normalizes to exactly 12 chars, all in [alphabet].
  static bool isValid(String input) {
    final n = normalize(input);
    if (n.length != length) return false;
    return n.split('').every(alphabet.contains);
  }

  /// Formats a code as `XXXX-XXXX-XXXX` for display. Returns [code] unchanged if
  /// it does not normalize to 12 chars.
  static String format(String code) {
    final n = normalize(code);
    if (n.length != length) return code;
    return '${n.substring(0, 4)}-${n.substring(4, 8)}-${n.substring(8, 12)}';
  }
}
```

- [ ] **Step 4: Run test, expect PASS** — `flutter test test/services/sync_code_test.dart`. (Fix the placeholder line in Step-1 test if it complained — replace the awkward `normalize('il o')` assertion with `expect(SyncCode.normalize(' a-b c '), 'ABC');`.)
- [ ] **Step 5: Commit** — `git add app/lib/services/sync_code.dart app/test/services/sync_code_test.dart && git commit -m "feat(sync): add SyncCode util (Crockford Base32, 12 chars)"`

---

### Task 2: `SyncProvider` — replace passphrase with sync code

**Files:**
- Modify: `app/lib/providers/sync_provider.dart`
- Test: `app/test/sync_provider_supabase_test.dart`

Changes:
- Add `import '../services/sync_code.dart';`
- Replace `_passphraseKey`/`_passphrase`/`passphrase`/`hasPassphrase`/`setPassphrase` with sync-code equivalents.
- Constants: `static const _syncCodeKey = 'sync_code';` and `static const _legacyPassphraseKey = 'sync_passphrase';`
- Getters: `String get syncCode => _syncCode;` `bool get hasSyncCode => _syncCode.length == SyncCode.length;` and change `enabled` to `isSupabaseConfigured && hasSyncCode`. Keep `isSupabaseConfigured` = url+anonKey.
- `_init`: load `_syncCode` from storage; `await _storage.deleteGenericSecret(_legacyPassphraseKey);`
- New methods:

```dart
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
```
- `clearSupabaseConfig`: delete `_syncCodeKey` secret and set `_syncCode = ''`.

- [ ] **Step 1: Add/adjust tests** in `app/test/sync_provider_supabase_test.dart`:

```dart
import 'package:yourssh/services/sync_code.dart';
// ... existing imports ...

test('enabled requires url, anonKey and a sync code', () async {
  final p = SyncProvider();
  await p.setSupabaseConfig('https://x.supabase.co', 'anon-key-abc');
  expect(p.isSupabaseConfigured, isTrue);
  expect(p.enabled, isFalse); // no code yet
});

test('generateSyncCode sets a valid 12-char code and enables sync', () async {
  final p = SyncProvider();
  await p.setSupabaseConfig('https://x.supabase.co', 'anon-key-abc');
  final code = await p.generateSyncCode();
  expect(SyncCode.isValid(code), isTrue);
  expect(p.syncCode, code);
  expect(p.hasSyncCode, isTrue);
  expect(p.enabled, isTrue);
});

test('setSyncCode normalizes input', () async {
  final p = SyncProvider();
  await p.setSyncCode('abcd-2345-efgh');
  expect(p.syncCode, 'ABCD2345EFGH');
});
```
(Note: these provider instances have no StorageService, so the code lives in memory only — fine for these assertions.)

- [ ] **Step 2: Run, expect FAIL** — `flutter test test/sync_provider_supabase_test.dart`.
- [ ] **Step 3: Implement** the provider changes above.
- [ ] **Step 4: Run, expect PASS** — `flutter test test/sync_provider_supabase_test.dart`.
- [ ] **Step 5: Commit** — `git add app/lib/providers/sync_provider.dart app/test/sync_provider_supabase_test.dart && git commit -m "feat(sync): SyncProvider uses sync code as the secret, drops passphrase"`

---

### Task 3: `SupabaseService` — key rows by the sync code

**Files:**
- Modify: `app/lib/services/supabase_service.dart`
- Test: `app/test/supabase_service_test.dart`

Changes:
- Constructor `SupabaseService(this._url, this._anonKey, this._syncCode);` add `final String _syncCode;` and `String get syncCode => _syncCode;`
- Replace `static const _rowKey = 'default';` — delete it; use `_syncCode` in `fetchPayload`/`fetchUpdatedAt`/`upsertPayload`/`deleteRow`.
- `migrationSql` becomes the 12-char form:

```dart
  static const migrationSql = '''
create table if not exists sync_data (
  sync_id    text        primary key check (char_length(sync_id) = 12),
  payload    text        not null,
  updated_at timestamptz not null default now()
);
alter table sync_data enable row level security;
drop policy if exists "anon_rw" on sync_data;
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (char_length(sync_id) = 12);''';
```

- [ ] **Step 1: Update test** `app/test/supabase_service_test.dart`: change any `SupabaseService('url','key')` to `SupabaseService('https://x.supabase.co','anon','ABCD2345EFGH')`; keep the `contains('sync_data')` / `contains('row level security')` assertions; add `expect(SupabaseService.migrationSql, contains('char_length(sync_id) = 12'));`
- [ ] **Step 2: Run, expect FAIL** — `flutter test test/supabase_service_test.dart`.
- [ ] **Step 3: Implement** the service changes.
- [ ] **Step 4: Run, expect PASS** — `flutter test test/supabase_service_test.dart`.
- [ ] **Step 5: Commit** — `git add app/lib/services/supabase_service.dart app/test/supabase_service_test.dart && git commit -m "feat(sync): key Supabase rows by the sync code; restore 12-char schema"`

---

### Task 4: `SyncService` — encrypt with the sync code

**Files:**
- Modify: `app/lib/services/sync_service.dart`
- Test: `app/test/services/sync_service_test.dart`

Changes:
- `_getSupabase()`: return null unless `isSupabaseConfigured && hasSyncCode`; build `SupabaseService(url, key, code)`; extend cache key with `_cachedSupabase!.syncCode != code`.
- `push`: after `if (!_syncProvider.enabled) return;`, the enabled flag already requires a code — but make the missing-code case explicit:
```dart
if (!_syncProvider.isSupabaseConfigured) return;
if (!_syncProvider.hasSyncCode) {
  _syncProvider.setError('Generate or enter a sync code in Settings → Sync.');
  return;
}
```
  (Replace the old `if (!_syncProvider.enabled) return;` line.)
- `push` encrypt call: `SyncEncryption.encrypt(payload, _syncProvider.syncCode)` (remove `passphrase:`).
- `pull` decrypt call: `SyncEncryption.decrypt(encrypted, _syncProvider.syncCode)` (remove `passphrase:`).

- [ ] **Step 1: Update test** `app/test/services/sync_service_test.dart`:
  - Fix `_ThrowingSupabase` constructor: `_ThrowingSupabase() : super('https://test.supabase.co', 'test-anon-key', 'ABCD2345EFGH');`
  - In the roundtrip test, rename the secret to a real code: replace `const anonKey = 'anon-key-abc';` with `const code = 'ABCD2345EFGH';` and use `code` in the encrypt/decrypt calls.
- [ ] **Step 2: Run, expect FAIL** — `flutter test test/services/sync_service_test.dart`.
- [ ] **Step 3: Implement** the service changes.
- [ ] **Step 4: Run, expect PASS** — `flutter test test/services/sync_service_test.dart`.
- [ ] **Step 5: Commit** — `git add app/lib/services/sync_service.dart app/test/services/sync_service_test.dart && git commit -m "feat(sync): encrypt/decrypt payload with the sync code"`

---

### Task 5: Settings UI — sync code section

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

Changes in `_SyncSectionState`:
- Replace `_passphraseController`/`_showPassphrase` with `_syncCodeController` / `_showSyncCode`; dispose accordingly; in `initState` set `_syncCodeController.text = SyncCode.format(widget.sync.syncCode);` and in `didUpdateWidget` keep it synced.
- `_testAndSave`: change `final svc = SupabaseService(url, anonKey);` to `SupabaseService(url, anonKey, '');` (connectivity check needs no code).
- Replace `_savePassphrase()` with:

```dart
Future<void> _generateCode() async {
  final code = await context.read<SyncProvider>().generateSyncCode();
  if (!mounted) return;
  setState(() => _syncCodeController.text = SyncCode.format(code));
  await _pushNow();
}

Future<void> _saveCode() async {
  final input = _syncCodeController.text;
  if (!SyncCode.isValid(input)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Enter a valid 12-character sync code.'), backgroundColor: Colors.red));
    return;
  }
  await context.read<SyncProvider>().setSyncCode(input);
  if (!mounted) return;
  setState(() => _syncCodeController.text = SyncCode.format(context.read<SyncProvider>().syncCode));
  await _pushNow();
}
```
- Replace the passphrase block inside `if (sync.isSupabaseConfigured) ...[` with a sync-code block: a label + helper text ("This code is the only key to your synced data. Save it — you'll need it on other devices."), a `TextField` bound to `_syncCodeController` (obscure when `!_showSyncCode`, reveal + copy icons), a **Generate** button when `!sync.hasSyncCode`, and a **Save** button to apply a typed code. Use the existing `_syncFieldDecoration` and button styling. Add `import '../services/sync_code.dart';`.
- Remove now-dead references to `passphrase`/`hasPassphrase`.

- [ ] **Step 1:** Apply the edits above.
- [ ] **Step 2: Analyze** — `flutter analyze lib/widgets/settings_screen.dart` → expect "No issues found!".
- [ ] **Step 3: Commit** — `git add app/lib/widgets/settings_screen.dart && git commit -m "feat(sync): Settings sync-code UI (generate / enter / reveal / copy)"`

---

### Task 6: Docs + full verification

**Files:**
- Modify: `CHANGELOG.md`, `README.md` (Credentials & Security bullet), `docs/roadmap.md`

- [ ] **Step 1:** Add a CHANGELOG `### Added`/`### Changed` entry under `[0.1.14]`: "Cloud sync now uses a 12-char sync code as the single encryption secret and row key (replaces anon-key-derived encryption + passphrase)."
- [ ] **Step 2:** Update the README "Zero-knowledge cloud sync" bullet to mention the sync code, and the roadmap current-version note.
- [ ] **Step 3: Full analyze** — `cd app && flutter analyze` → expect no new issues.
- [ ] **Step 4: Full test** — `cd app && flutter test` → expect all pass.
- [ ] **Step 5: Commit** — `git add CHANGELOG.md README.md docs/roadmap.md && git commit -m "docs: document sync-code encryption model"`

---

## Self-Review notes
- Spec coverage: SyncCode (Task 1), provider/secret (Task 2), row key + schema (Task 3, 5-revert in Task 0), KDF wiring + missing-code guard (Task 4), UI (Task 5), docs/tests (Task 6). All spec sections covered.
- The Step-1 `normalize('il o')` assertion in Task 1 is awkward; use `expect(SyncCode.normalize(' a-b c '), 'ABC');` instead.
- Type consistency: `hasSyncCode`, `syncCode`, `setSyncCode`, `generateSyncCode`, `SupabaseService(url, anonKey, syncCode)` used consistently across tasks.
