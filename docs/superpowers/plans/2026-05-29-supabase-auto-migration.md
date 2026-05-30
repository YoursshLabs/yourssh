# Supabase Auto-Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** When a user enters Supabase URL + anon key + service role key and the `sync_data` table is missing, auto-run the SQL migration so they never have to touch the Supabase dashboard.

**Architecture:** `SupabaseService` gains a `setupSchema(serviceRoleKey)` method that POSTs the migration SQL to Supabase's internal `pg/query` endpoint. `testConnection()` is updated to return an enum that distinguishes "table not found" from other errors, letting `_SyncSectionState._testAndSave()` trigger migration automatically before re-testing.

**Tech Stack:** Flutter, `supabase_flutter 2.5.0`, `http ^1.2.0` (new dependency), `dart:convert`

---

### Task 1: Add `http` package dependency

**Files:**
- Modify: `app/pubspec.yaml`

- [x] **Step 1: Add http dependency**

In `app/pubspec.yaml`, under `dependencies:`, add after the `supabase_flutter` line:

```yaml
  http: ^1.2.0
```

- [x] **Step 2: Install the package**

```bash
cd app && flutter pub get
```

Expected output: `Got dependencies!` with no errors.

- [x] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "chore: add http package for supabase migration API calls"
```

---

### Task 2: Update `SupabaseService` with auto-migration support

**Files:**
- Modify: `app/lib/services/supabase_service.dart`
- Modify: `app/test/supabase_service_test.dart`

- [x] **Step 1: Write tests first**

Replace the full content of `app/test/supabase_service_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yourssh/services/supabase_service.dart';

class _SuccessHttpSupabase extends SupabaseService {
  _SuccessHttpSupabase() : super('https://abc.supabase.co', 'anon-key');

  @override
  Future<http.Response> doPost(
      Uri uri, Map<String, String> headers, String body) async {
    return http.Response('{"result":[]}', 200);
  }
}

class _FailHttpSupabase extends SupabaseService {
  final int statusCode;
  _FailHttpSupabase(this.statusCode) : super('https://abc.supabase.co', 'anon-key');

  @override
  Future<http.Response> doPost(
      Uri uri, Map<String, String> headers, String body) async {
    return http.Response('{"error":"unauthorized"}', statusCode);
  }
}

class _ThrowingHttpSupabase extends SupabaseService {
  _ThrowingHttpSupabase() : super('https://abc.supabase.co', 'anon-key');

  @override
  Future<http.Response> doPost(
      Uri uri, Map<String, String> headers, String body) async {
    throw Exception('network error');
  }
}

void main() {
  test('stores url and anonKey via constructor', () {
    final svc = SupabaseService('https://abc.supabase.co', 'anon-key-123');
    expect(svc.url, 'https://abc.supabase.co');
    expect(svc.anonKey, 'anon-key-123');
  });

  group('SupabaseService.setupSchema', () {
    test('returns success when pg/query responds 200', () async {
      final svc = _SuccessHttpSupabase();
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isTrue);
      expect(error, isNull);
    });

    test('returns failure with message on non-200 response', () async {
      final svc = _FailHttpSupabase(401);
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isFalse);
      expect(error, contains('401'));
    });

    test('returns failure with message on network exception', () async {
      final svc = _ThrowingHttpSupabase();
      final (ok, error) = await svc.setupSchema('service-role-key');
      expect(ok, isFalse);
      expect(error, contains('network error'));
    });

    test('posts to correct url with correct headers', () async {
      late Uri capturedUri;
      late Map<String, String> capturedHeaders;

      final svc = _SuccessHttpSupabase();
      // ignore: prefer_function_declarations_over_variables
      svc.testDoPost = (uri, headers, body) async {
        capturedUri = uri;
        capturedHeaders = headers;
        return http.Response('{}', 200);
      };

      await svc.setupSchema('my-service-role-key');
      expect(capturedUri.toString(), 'https://abc.supabase.co/pg/query');
      expect(capturedHeaders['apikey'], 'my-service-role-key');
      expect(capturedHeaders['Authorization'], 'Bearer my-service-role-key');
    });
  });
}
```

- [x] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/supabase_service_test.dart
```

Expected: FAIL — `setupSchema`, `doPost`, `TestConnectionOutcome` not defined yet.

- [x] **Step 3: Update `supabase_service.dart`**

Replace the full content of `app/lib/services/supabase_service.dart` with:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

enum TestConnectionOutcome { connected, tableNotFound, failed }

class SupabaseService {
  static const _migrationSql = '''
create table if not exists sync_data (
  sync_id    text        primary key check (char_length(sync_id) = 12),
  payload    text        not null,
  updated_at timestamptz not null default now()
);
alter table sync_data enable row level security;
create policy "anon_rw" on sync_data
  for all
  to anon
  using (true)
  with check (char_length(sync_id) = 12);
''';

  final String _url;
  final String _anonKey;
  SupabaseClient? _clientInstance;

  // Override in tests to inject a fake HTTP implementation.
  Future<http.Response> Function(
      Uri, Map<String, String>, String)? testDoPost;

  SupabaseService(this._url, this._anonKey);

  SupabaseClient get _client =>
      _clientInstance ??= SupabaseClient(_url, _anonKey);

  String get url => _url;
  String get anonKey => _anonKey;

  /// Override in tests; calls [testDoPost] if set, otherwise real http.post.
  Future<http.Response> doPost(
      Uri uri, Map<String, String> headers, String body) {
    if (testDoPost != null) return testDoPost!(uri, headers, body);
    return http.post(uri, headers: headers, body: body);
  }

  /// Returns (TestConnectionOutcome, errorMessage).
  Future<(TestConnectionOutcome, String?)> testConnection() async {
    try {
      await _client.from('sync_data').select('sync_id').limit(1);
      return (TestConnectionOutcome.connected, null);
    } on PostgrestException catch (e) {
      if (e.code == '42P01') {
        return (TestConnectionOutcome.tableNotFound, null);
      }
      return (TestConnectionOutcome.failed, e.message);
    } catch (e) {
      return (TestConnectionOutcome.failed, e.toString());
    }
  }

  /// Runs the sync_data schema migration via the Supabase pg/query endpoint.
  /// Requires the project's service role key (not stored — only used once).
  Future<(bool, String?)> setupSchema(String serviceRoleKey) async {
    try {
      final uri = Uri.parse('$_url/pg/query');
      final response = await doPost(
        uri,
        {
          'Content-Type': 'application/json',
          'apikey': serviceRoleKey,
          'Authorization': 'Bearer $serviceRoleKey',
        },
        jsonEncode({'query': _migrationSql}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return (true, null);
      }
      return (false, 'Migration failed (HTTP ${response.statusCode}): ${response.body}');
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

- [x] **Step 4: Run tests to confirm they pass**

```bash
cd app && flutter test test/supabase_service_test.dart
```

Expected: All tests PASS. (The `testDoPost` injection test relies on the field set before `setupSchema` is called — verify the test runs correctly.)

- [x] **Step 5: Run full test suite to check for regressions**

```bash
cd app && flutter test
```

Expected: All tests pass. If `sync_service_test.dart` fails because it uses the old `(bool, String?)` return type from `testConnection`, it likely doesn't call `testConnection` — check grep output and fix if needed.

- [x] **Step 6: Commit**

```bash
git add app/lib/services/supabase_service.dart app/test/supabase_service_test.dart
git commit -m "feat: add setupSchema auto-migration to SupabaseService"
```

---

### Task 3: Update Settings UI for auto-migration flow

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

- [x] **Step 1: Add new state fields to `_SyncSectionState`**

In `_SyncSectionState`, after `bool _testing = false;` (line ~253), add:

```dart
  bool _migrating = false;
  bool _tableCreated = false;
  final _serviceRoleKeyController = TextEditingController();
  bool _showServiceRoleKey = false;
```

- [x] **Step 2: Update `dispose()` in `_SyncSectionState`**

The current `dispose()` disposes 3 controllers. Add the new one:

```dart
  @override
  void dispose() {
    _codeController.dispose();
    _urlController.dispose();
    _anonKeyController.dispose();
    _serviceRoleKeyController.dispose();
    super.dispose();
  }
```

- [x] **Step 3: Replace `_testAndSave()` with the new auto-migration flow**

Replace the existing `_testAndSave()` method (lines ~300-318) with:

```dart
  Future<void> _testAndSave() async {
    final url = _urlController.text.trim();
    final anonKey = _anonKeyController.text.trim();
    final serviceRoleKey = _serviceRoleKeyController.text.trim();
    if (url.isEmpty || anonKey.isEmpty) {
      setState(() { _testError = 'URL and anon key are required'; _testOk = false; });
      return;
    }
    setState(() { _testing = true; _testError = null; _testOk = false; _tableCreated = false; });
    try {
      final svc = SupabaseService(url, anonKey);
      final (outcome, error) = await svc.testConnection();
      if (!mounted) return;

      if (outcome == TestConnectionOutcome.connected) {
        await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
        if (!mounted) return;
        setState(() { _testing = false; _testOk = true; });
        return;
      }

      if (outcome == TestConnectionOutcome.tableNotFound && serviceRoleKey.isNotEmpty) {
        setState(() { _testing = false; _migrating = true; });
        final (ok, migrateError) = await svc.setupSchema(serviceRoleKey);
        if (!mounted) return;
        if (!ok) {
          setState(() { _migrating = false; _testError = migrateError; });
          return;
        }
        final (outcome2, error2) = await svc.testConnection();
        if (!mounted) return;
        if (outcome2 == TestConnectionOutcome.connected) {
          await context.read<SyncProvider>().setSupabaseConfig(url, anonKey);
          if (!mounted) return;
          setState(() { _migrating = false; _testOk = true; _tableCreated = true; });
        } else {
          setState(() { _migrating = false; _testError = error2 ?? 'Connection failed after migration'; });
        }
        return;
      }

      // tableNotFound but no service role key, or other error
      final message = outcome == TestConnectionOutcome.tableNotFound
          ? 'Table not found. Add your Service Role Key above to auto-create it.'
          : (error ?? 'Connection failed');
      setState(() { _testing = false; _testError = message; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _testing = false; _migrating = false; _testError = e.toString(); });
    }
  }
```

- [x] **Step 4: Replace `_buildTestStatus()` to handle migrating state**

Replace the existing `_buildTestStatus()` method with:

```dart
  Widget _buildTestStatus() {
    if (_migrating) {
      return const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
        SizedBox(width: 6),
        Text('Setting up database…', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ]);
    }
    if (_testing) return const SizedBox.shrink();
    if (_testOk) {
      final label = _tableCreated ? 'Connected (table created)' : 'Connected';
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, size: 12, color: Colors.green),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.green, fontSize: 11)),
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

- [x] **Step 5: Add the Service Role Key field to the UI**

In the `build()` method of `_SyncSectionState`, locate the anon key `Row(children: [...])` block (ends with the "Save & Test" button, around line ~459-476). Add the service role key field immediately after that Row and before the status line (`if (_testing || _testOk || _testError != null)`):

```dart
                      const SizedBox(height: 8),
                      TextField(
                        controller: _serviceRoleKeyController,
                        obscureText: !_showServiceRoleKey,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Service Role Key (optional — for auto table setup)',
                          hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                          filled: true,
                          fillColor: AppColors.bg,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.accent)),
                          suffixIcon: IconButton(
                            icon: Icon(_showServiceRoleKey ? Icons.visibility_off : Icons.visibility, size: 16, color: AppColors.textTertiary),
                            onPressed: () => setState(() => _showServiceRoleKey = !_showServiceRoleKey),
                          ),
                        ),
                      ),
```

- [x] **Step 6: Add the `TestConnectionOutcome` import**

The `TestConnectionOutcome` enum is defined in `supabase_service.dart`, which is already imported at the top of `settings_screen.dart`. No import change needed.

- [x] **Step 7: Analyze for compile errors**

```bash
cd app && flutter analyze lib/widgets/settings_screen.dart
```

Expected: No errors. Fix any type mismatches (old `(bool, String?)` → new `(TestConnectionOutcome, String?)`).

- [x] **Step 8: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat: auto-run migration when service role key provided and table missing"
```

---

### Task 4: Update SYNC_SETUP.md documentation

**Files:**
- Modify: `docs/SYNC_SETUP.md`

- [x] **Step 1: Update the migration section to mention auto-setup**

Find the `## 2. Run the migration to create the table` section. Replace it with:

```markdown
## 2. Create the sync_data table

### Option A — Automatic in the app (recommended)

When entering **Project URL** and **Anon Key**, also add the **Service Role Key** in the field below and click **Save & Test**.
The app will automatically create the `sync_data` table and configure the RLS policy — no manual steps needed.

Get the Service Role Key at: **Project Settings → API → Project API keys → `service_role`** (click Reveal).

> The Service Role Key is only used once for setup — the app does not store it after the migration succeeds.

### Option B — Supabase Dashboard (manual)

1. Go to **SQL Editor** in the dashboard
2. Copy the contents of `supabase/migrations/20260529000000_sync_data.sql`
3. Paste → **Run**

### Option C — Supabase CLI

```bash
brew install supabase/tap/supabase
supabase link --project-ref <your-project-ref>
supabase db push
```
```

- [x] **Step 2: Commit**

```bash
git add docs/SYNC_SETUP.md
git commit -m "docs: update SYNC_SETUP to document auto-migration via service role key"
```

---

### Task 5: Final verification

- [x] **Step 1: Run full test suite**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [x] **Step 2: Analyze entire app**

```bash
cd app && flutter analyze
```

Expected: No errors (warnings OK).
