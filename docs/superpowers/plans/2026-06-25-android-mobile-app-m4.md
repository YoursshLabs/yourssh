# Android Mobile App — Milestone 4 (SFTP + Snippets) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Android, insert reusable snippets into the live terminal, and browse / download / upload files over SFTP on a connected host (single-panel).

**Architecture:** Reuse the existing `yourssh_snippets` `SnippetProvider` (standalone — not the plugin wrapper) for snippets, inserting `snippet.command` into the active session's xterm `Terminal.textInput`. SFTP mirrors the desktop `sftp_screen.dart`: `SshService.openSftp(host)` → `sftp.listdir(path)` over the active SSH session's already-connected client, with `file_picker` for upload (pick) and download (pick destination dir). No new dependencies.

**Tech Stack:** Flutter, `provider`, `yourssh_snippets`, `dartssh2` SFTP, `file_picker`, `path`.

## Global Constraints

- Dart package `yourssh`; dark-only (`AppColors`); reuse existing classes; don't touch desktop bootstrap/widgets.
- SFTP operates on the **active SSH session's host** (its SSH client is already open); if there is no connected SSH session, the SFTP tab shows a "connect a host first" state.
- Snippets insert text only (no auto-Enter) so the user can review before running.
- Desktop builds + full `flutter test` + `flutter analyze` MUST stay green.
- No Claude attribution. Commit after each task. Branch `feat/android-mobile-app`.

## Key existing APIs (verified)

- `SnippetProvider()` (from `package:yourssh_snippets/yourssh_snippets.dart`) auto-loads (defaults if empty); `snippets` (List<Snippet>); `filterSnippets(List<Snippet>, String query)`. `Snippet` has `id`, `label`, `command`, `description`, `tag`.
- `SessionProvider.activeSshSession` → `SshSession?`; `SshSession.terminal` (xterm `Terminal`), `.host`.
- `SshService.openSftp(Host)` → `Future<SftpClient>` (reuses the open client). `SftpClient.listdir(path)` → `List<SftpName>` (`filename`, `attr.isDirectory`, `attr.size`), `.open(path)` → `SftpFile` (`readBytes()`, `close()`).
- `SftpTransferService(SshService).uploadFile(Host, String localPath, String remotePath)`.
- `file_picker`: `FilePicker.platform.pickFiles()` (upload source, `.files.single.path`), `FilePicker.platform.getDirectoryPath()` (download destination — Android SAF tree).
- `Terminal.textInput(String)`.

---

## Phase M4.1 — Snippets quick-insert

### Task 1: Add SnippetProvider + SftpTransferService to the bootstrap

**Files:**
- Modify: `app/lib/mobile/mobile_bootstrap.dart`
- Test: `app/test/mobile/mobile_bootstrap_test.dart` (extend)

**Interfaces:**
- Produces: `MobileBootstrap.snippets` (SnippetProvider) and `MobileBootstrap.transfer` (SftpTransferService); SnippetProvider added to `providers`, SftpTransferService as a plain Provider.

- [ ] **Step 1: Extend the bootstrap test**

Add inside `main()` of `app/test/mobile/mobile_bootstrap_test.dart`:
```dart
  test('exposes snippets + transfer service', () {
    final b = MobileBootstrap();
    expect(b.snippets, isNotNull);
    expect(b.transfer, isNotNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_bootstrap_test.dart`
Expected: FAIL — `snippets`/`transfer` undefined.

- [ ] **Step 3: Add to the bootstrap**

In `app/lib/mobile/mobile_bootstrap.dart` add imports:
```dart
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../services/sftp_transfer_service.dart';
```
Add fields:
```dart
  late final SnippetProvider snippets;
  late final SftpTransferService transfer;
```
In the constructor (after `syncService = ...`):
```dart
    snippets = SnippetProvider();
    transfer = SftpTransferService(ssh);
```
Add to `providers`:
```dart
        ChangeNotifierProvider.value(value: snippets),
        Provider.value(value: transfer),
```

> Verify at execution: `SftpTransferService`'s constructor argument (it takes the `SshService`). If its ctor differs, match it.

- [ ] **Step 4: Run test + analyze**

Run: `cd app && flutter test test/mobile/mobile_bootstrap_test.dart && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/mobile_bootstrap.dart app/test/mobile/mobile_bootstrap_test.dart
git commit -m "feat(mobile): add snippets + transfer service to bootstrap"
```

---

### Task 2: Snippets sheet + insert into the terminal

**Files:**
- Create: `app/lib/mobile/terminal/mobile_snippets_sheet.dart`
- Modify: `app/lib/mobile/screens/mobile_sessions_screen.dart` (snippets button → open sheet → insert into active terminal)
- Test: `app/test/mobile/mobile_snippets_sheet_test.dart`

**Interfaces:**
- Produces: `class MobileSnippetsSheet extends StatefulWidget` taking `void Function(String command) onInsert`; searchable list of `SnippetProvider.snippets` via `filterSnippets`; tapping a row calls `onInsert(snippet.command)` then pops. The Sessions screen opens it via `showModalBottomSheet` and inserts into `activeSession.terminal`.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_snippets_sheet_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh/mobile/terminal/mobile_snippets_sheet.dart';

Future<void> _pump(WidgetTester tester, {required void Function(String) onInsert}) async {
  final sp = SnippetProvider();
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider.value(
      value: sp,
      child: Scaffold(body: MobileSnippetsSheet(onInsert: onInsert)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a snippet inserts its command', (tester) async {
    String? inserted;
    await _pump(tester, onInsert: (c) => inserted = c);

    // SnippetProvider seeds defaults; tap the first snippet row.
    final firstTile = find.byType(ListTile).first;
    expect(firstTile, findsOneWidget);
    await tester.tap(firstTile);
    await tester.pumpAndSettle();

    expect(inserted, isNotNull);
    expect(inserted!.isNotEmpty, isTrue);
  });

  testWidgets('search filters the list', (tester) async {
    await _pump(tester, onInsert: (_) {});
    final before = tester.widgetList(find.byType(ListTile)).length;
    await tester.enterText(find.byType(TextField), 'zzz-no-match-xyz');
    await tester.pumpAndSettle();
    final after = tester.widgetList(find.byType(ListTile)).length;
    expect(after, lessThanOrEqualTo(before));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_snippets_sheet_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the sheet**

Create `app/lib/mobile/terminal/mobile_snippets_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../theme/app_theme.dart';

/// Bottom-sheet list of snippets; tapping one inserts its command into the
/// active terminal (via [onInsert]) and closes the sheet.
class MobileSnippetsSheet extends StatefulWidget {
  final void Function(String command) onInsert;
  const MobileSnippetsSheet({super.key, required this.onInsert});

  @override
  State<MobileSnippetsSheet> createState() => _MobileSnippetsSheetState();
}

class _MobileSnippetsSheetState extends State<MobileSnippetsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<SnippetProvider>().snippets;
    final shown = filterSnippets(all, _query);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search snippets',
                prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No snippets',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final s = shown[i];
                        return ListTile(
                          title: Text(s.label,
                              style: const TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(s.command,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                          onTap: () {
                            widget.onInsert(s.command);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/mobile_snippets_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire a snippets button into the Sessions screen**

In `mobile_sessions_screen.dart`:
- Import `'../terminal/mobile_snippets_sheet.dart';`.
- Pass an `onSnippets` callback into `_SessionStrip` and render a trailing `IconButton(icon: Icon(Icons.code))` after the chips.
- In the state, implement `_openSnippets(SshSession active)`:
```dart
  void _openSnippets(SshSession active) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (_) => MobileSnippetsSheet(
        onInsert: (cmd) => active.terminal.textInput(cmd),
      ),
    );
  }
```
- Wire `_SessionStrip(..., onSnippets: () => _openSnippets(active))`. Add `final VoidCallback onSnippets;` to `_SessionStrip` and the trailing button.

- [ ] **Step 6: Run mobile tests + analyze**

Run: `cd app && flutter test test/mobile/ && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/mobile/terminal/mobile_snippets_sheet.dart app/lib/mobile/screens/mobile_sessions_screen.dart app/test/mobile/mobile_snippets_sheet_test.dart
git commit -m "feat(mobile): snippets sheet inserts into terminal"
```

---

## Phase M4.2 — SFTP single-panel

### Task 3: SFTP browser (list + navigate)

**Files:**
- Create: `app/lib/mobile/screens/mobile_sftp_screen.dart`
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart` (index 2 → SFTP screen)
- Test: `app/test/mobile/mobile_sftp_screen_test.dart`

**Interfaces:**
- Consumes: `SessionProvider.activeSshSession`, `SshService.openSftp`, `SftpClient.listdir`.
- Produces: `class MobileSftpScreen extends StatefulWidget` — no connected SSH session → "Connect a host to browse files"; else list the remote dir (dirs first), breadcrumb path, tap dir to descend, up button to ascend.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_sftp_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_sftp_screen.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows connect prompt with no SSH session', (tester) async {
    final storage = StorageService();
    final ssh = SshService(storage);
    final sp = SessionProvider(ssh, TabMetadataService());
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: sp),
          Provider<SshService>.value(value: ssh),
        ],
        child: const MobileSftpScreen(),
      ),
    ));
    expect(find.textContaining('Connect a host'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_sftp_screen_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the SFTP screen**

Create `app/lib/mobile/screens/mobile_sftp_screen.dart`:
```dart
import 'dart:io' as io;

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../providers/session_provider.dart';
import '../../services/sftp_transfer_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';

/// Single-panel SFTP browser over the active SSH session's host. Lists, opens
/// directories, downloads files to a picked folder, and uploads a picked file.
class MobileSftpScreen extends StatefulWidget {
  const MobileSftpScreen({super.key});

  @override
  State<MobileSftpScreen> createState() => _MobileSftpScreenState();
}

class _MobileSftpScreenState extends State<MobileSftpScreen> {
  String _path = '.';
  List<SftpName> _entries = [];
  bool _loading = false;
  String? _error;
  String? _loadedHostId;

  Future<void> _load(Host host, String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sftp = await context.read<SshService>().openSftp(host);
      final raw = await sftp.listdir(path);
      sftp.close();
      raw.sort((a, b) {
        final ad = a.attr.isDirectory, bd = b.attr.isDirectory;
        if (ad != bd) return ad ? -1 : 1;
        return a.filename.compareTo(b.filename);
      });
      if (!mounted) return;
      setState(() {
        _path = path;
        _entries = raw.where((e) => e.filename != '.' && e.filename != '..').toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _maybeLoad(Host host) {
    if (_loadedHostId == host.id) return;
    _loadedHostId = host.id;
    _path = '.';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(host, '.'));
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<SessionProvider>().activeSshSession;
    if (active == null) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('Connect a host to browse files',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final host = active.host;
    _maybeLoad(host);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _upload(host),
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.upload_file, color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _bar(host),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (_, i) => _row(host, _entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(Host host) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: AppColors.card,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: AppColors.textSecondary),
            onPressed: _path == '.' || _path == '/'
                ? null
                : () => _load(host, p.posix.dirname(_path)),
          ),
          Expanded(
            child: Text(_path,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () => _load(host, _path),
          ),
        ],
      ),
    );
  }

  Widget _row(Host host, SftpName e) {
    final isDir = e.attr.isDirectory;
    return ListTile(
      leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file,
          color: isDir ? AppColors.accent : AppColors.textSecondary),
      title: Text(e.filename, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: isDir
          ? null
          : Text('${e.attr.size ?? 0} bytes',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      trailing: isDir
          ? null
          : IconButton(
              icon: const Icon(Icons.download, color: AppColors.textSecondary),
              onPressed: () => _download(host, e),
            ),
      onTap: isDir ? () => _load(host, _join(e.filename)) : null,
    );
  }

  String _join(String name) =>
      _path == '.' ? name : p.posix.join(_path, name);

  Future<void> _download(Host host, SftpName e) async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    try {
      final sftp = await context.read<SshService>().openSftp(host);
      final file = await sftp.open(_join(e.filename));
      final bytes = await file.readBytes();
      await file.close();
      sftp.close();
      await io.File(p.join(dir, e.filename)).writeAsBytes(bytes);
      _snack('Downloaded ${e.filename}');
    } catch (err) {
      _snack('Download failed: $err');
    }
  }

  Future<void> _upload(Host host) async {
    final picked = await FilePicker.platform.pickFiles();
    final localPath = picked?.files.single.path;
    if (localPath == null) return;
    final name = p.basename(localPath);
    try {
      await context
          .read<SftpTransferService>()
          .uploadFile(host, localPath, _join(name));
      _snack('Uploaded $name');
      _load(host, _path);
    } catch (err) {
      _snack('Upload failed: $err');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
```

> Verify at execution: `package:dartssh2/dartssh2.dart` exports `SftpName`/`SftpFile`. `path` package is a dependency (`p.posix`). `FilePicker.platform.getDirectoryPath()` exists in file_picker 8.

- [ ] **Step 4: Wire into the shell (index 2)**

In `mobile_home_shell.dart`, import `mobile_sftp_screen.dart` and add `case 2: return const MobileSftpScreen();` (so `default` now only covers nothing — keep a `default` returning an empty `SizedBox.shrink()` or the placeholder for safety).

- [ ] **Step 5: Run test to verify it passes + analyze**

Run: `cd app && flutter test test/mobile/mobile_sftp_screen_test.dart && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/mobile/screens/mobile_sftp_screen.dart app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/mobile_sftp_screen_test.dart
git commit -m "feat(mobile): single-panel SFTP browser + download/upload"
```

---

### Task 4: Build + regression

**Files:** none (verification)

- [ ] **Step 1: Full test suite**

Run: `cd app && flutter test`
Expected: all tests pass.

- [ ] **Step 2: Analyze whole repo**

Run: `cd app && flutter analyze`
Expected: no NEW issues (the 2 pre-existing `integration_test` probe warnings may remain).

- [ ] **Step 3: Build the APK**

Run: `cd app && flutter build apk --debug`
Expected: `✓ Built ... app-debug.apk`.

- [ ] **Step 4: Restore any regenerated desktop registrants**

```bash
git checkout HEAD -- app/macos/Flutter/GeneratedPluginRegistrant.swift app/windows/flutter/generated_plugin_registrant.cc app/windows/flutter/generated_plugins.cmake 2>/dev/null || true
```

- [ ] **Step 5: On-device (user, when available)**

Manual: connect a host → Sessions → snippets button → tap a snippet (inserts into terminal) → SFTP tab → browse, download a file (pick folder), upload a file (pick file).

---

## Self-Review

**Spec coverage (M4):**
- "SFTP browser — single-panel mobile layout (remote only); browse, upload, download" → Tasks 3 (+ download/upload in the same screen). ✓
- "Snippets … insert into the active session" → Tasks 1, 2. ✓
- "command history" → **deferred** (documented below): mobile types directly into xterm with no input bar to capture commands; revisit when/if an optional input bar lands.

**Placeholder scan:** No vague steps; code complete. The `> Verify at execution` notes (SftpTransferService ctor arg, dartssh2 exports, file_picker API) name concrete checks.

**Type consistency:** `MobileBootstrap.snippets`/`transfer` (Task 1) consumed by the snippets sheet (Task 2, via provider) and the SFTP screen (Task 3, `context.read<SftpTransferService>()`). `MobileSnippetsSheet(onInsert:)` matches the Sessions-screen wiring. `_join`/`_load(host, path)` consistent within the SFTP screen.

## Deferred

- **Command history** on mobile (no input bar to capture commands; needs an optional input-bar capture mechanism first).
- SFTP rename/delete/mkdir/permissions, multi-select, transfer queue UI → later (download/upload cover the core).
- TOFU mismatch dialog, appearance, app-lock, release signing → M5.
