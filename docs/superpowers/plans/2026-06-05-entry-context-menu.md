# Entry Context Menu Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unified right-click context menu for both SFTP panels (remote + local) with Open/Open with/Copy to target directory/Rename/Delete/Refresh/New Folder/Edit Permissions, per spec `docs/superpowers/specs/2026-06-05-entry-context-menu-design.md`.

**Architecture:** Generalize the existing MenuAnchor-based `SftpEntryContextMenu` into a shared `EntryContextMenu` used by both panels. `DualPanelSftpScreen` injects copy-to-target callbacks (reusing its transfer matrix). New chmod support: `SftpEntry.mode` field, `SftpFileOpsService.chmod` (callback-injected recursion for testability, same pattern as `SftpTransferService.pipeChunks`), local chmod via `Process.run`, and a `PermissionsDialog` with a 9-checkbox rwx grid synced to an octal field.

**Tech Stack:** Flutter (macOS/Windows/Linux), dartssh2 local fork (`setStat`/`SftpFileMode`), provider, url_launcher, file_selector.

**Conventions:** All code/comments in English. Run commands from `app/`. Commit after each task.

---

### Task 1: Pure mode helpers (`file_mode.dart`)

**Files:**
- Create: `app/lib/util/file_mode.dart`
- Test: `app/test/util/file_mode_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/util/file_mode_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/file_mode.dart';

void main() {
  group('modeToOctal', () {
    test('formats common permission bits', () {
      expect(modeToOctal(0x1ED), '755'); // 0o755
      expect(modeToOctal(0x1A4), '644'); // 0o644
      expect(modeToOctal(0), '000');
    });

    test('masks file-type bits and keeps special bits', () {
      // Regular file (0o100644) -> '644'
      expect(modeToOctal(0x81A4), '644');
      // setuid + 0o755 (0o4755)
      expect(modeToOctal(0x9ED), '4755');
    });
  });

  group('parseOctal', () {
    test('parses 3- and 4-digit octal strings', () {
      expect(parseOctal('755'), 0x1ED);
      expect(parseOctal('0644'), 0x1A4);
      expect(parseOctal('4755'), 0x9ED);
    });

    test('rejects invalid input', () {
      expect(parseOctal(''), isNull);
      expect(parseOctal('78'), isNull); // 8 is not an octal digit
      expect(parseOctal('77777'), isNull); // too long
      expect(parseOctal('abc'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/util/file_mode_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh/util/file_mode.dart'` (file does not exist).

- [ ] **Step 3: Write the implementation**

```dart
// app/lib/util/file_mode.dart
import 'dart:io';

/// POSIX permission-bit helpers shared by the permissions dialog and the
/// local/remote chmod paths. Only the low 12 bits (0o7777: rwx for
/// owner/group/others plus setuid/setgid/sticky) are considered.

/// Formats the permission bits of [mode] as an octal string, e.g. 0o755 ->
/// '755', 0o4755 -> '4755'. File-type bits (above 0o7777) are masked off.
String modeToOctal(int mode) =>
    (mode & 0xFFF).toRadixString(8).padLeft(3, '0');

/// Parses a 3- or 4-digit octal permission string ('644', '0755', '4755')
/// into permission bits. Returns null when [text] is not valid octal.
int? parseOctal(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 4) return null;
  final value = int.tryParse(t, radix: 8);
  if (value == null || value < 0 || value > 0xFFF) return null;
  return value;
}

/// Applies [mode] to a local [path] via the system `chmod` (macOS/Linux
/// only — the caller hides the menu item on Windows).
Future<void> chmodLocal(String path, int mode,
    {bool recursive = false}) async {
  final result = await Process.run('chmod', [
    if (recursive) '-R',
    modeToOctal(mode),
    path,
  ]);
  if (result.exitCode != 0) {
    throw Exception('chmod failed: ${result.stderr}');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/util/file_mode_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/file_mode.dart app/test/util/file_mode_test.dart
git commit -m "feat: add POSIX mode helpers (octal parse/format, local chmod)"
```

---

### Task 2: `SftpEntry.mode` populated from listdir

**Files:**
- Modify: `app/lib/models/sftp_entry.dart`
- Modify: `app/lib/services/sftp_transfer_service.dart` (listDirectory, ~line 114)

- [ ] **Step 1: Add the optional `mode` field to `SftpEntry`**

In `app/lib/models/sftp_entry.dart`, add a field and constructor param (all existing call sites use named params, so an optional addition is non-breaking):

```dart
class SftpEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  /// Raw st_mode from the server (file-type + permission bits), null when
  /// the server did not report it. Used by the Edit Permissions dialog.
  final int? mode;

  const SftpEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    this.mode,
  });
  // ... rest unchanged
```

- [ ] **Step 2: Populate `mode` in `SftpTransferService.listDirectory`**

In the `SftpEntry` construction inside `listDirectory` (around line 116), add:

```dart
          SftpEntry(
            name: item.filename,
            path: p.posix.join(path, item.filename),
            isDirectory: isDir[i],
            size: item.attr.size ?? 0,
            mode: item.attr.mode?.value,
            modifiedAt: item.attr.modifyTime != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    item.attr.modifyTime! * 1000)
                : DateTime.now(),
          ),
```

- [ ] **Step 3: Verify**

Run: `cd app && flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add app/lib/models/sftp_entry.dart app/lib/services/sftp_transfer_service.dart
git commit -m "feat: carry st_mode on SftpEntry from directory listings"
```

---

### Task 3: `SftpFileOpsService.chmod` with testable recursion

**Files:**
- Modify: `app/lib/services/sftp_file_ops_service.dart`
- Test: `app/test/services/sftp_file_ops_service_test.dart` (new)

- [ ] **Step 1: Write the failing test**

The recursion driver is a static method with injected callbacks (the codebase pattern from `SftpTransferService.pipeChunks`) so it can be tested without a real `SftpClient`.

```dart
// app/test/services/sftp_file_ops_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sftp_file_ops_service.dart';

void main() {
  group('chmodWalk', () {
    // Fake tree: /a is a dir containing f1 and sub/, sub contains f2.
    final tree = <String, List<({String name, bool isDirectory})>>{
      '/a': [
        (name: 'f1', isDirectory: false),
        (name: 'sub', isDirectory: true),
      ],
      '/a/sub': [
        (name: 'f2', isDirectory: false),
      ],
    };

    test('non-recursive touches only the entry itself', () async {
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a',
        isDirectory: true,
        recursive: false,
        setMode: (p) async => touched.add(p),
        list: (p) async => tree[p]!,
      );
      expect(touched, ['/a']);
    });

    test('recursive walks the whole subtree depth-first', () async {
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a',
        isDirectory: true,
        recursive: true,
        setMode: (p) async => touched.add(p),
        list: (p) async => tree[p]!,
      );
      expect(touched, ['/a', '/a/f1', '/a/sub', '/a/sub/f2']);
    });

    test('recursive on a file does not list children', () async {
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a/f1',
        isDirectory: false,
        recursive: true,
        setMode: (p) async => touched.add(p),
        list: (p) async => fail('must not list a file'),
      );
      expect(touched, ['/a/f1']);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/sftp_file_ops_service_test.dart`
Expected: FAIL — `chmodWalk` is not defined.

- [ ] **Step 3: Implement chmod in `SftpFileOpsService`**

Append to the class in `app/lib/services/sftp_file_ops_service.dart`:

```dart
  /// Sets permission bits [mode] (e.g. 0x1ED for 0o755) on [path].
  /// With [recursive] and [isDirectory], applies the same bits to every
  /// child, like `chmod -R`.
  Future<void> chmod(Host host, String path, int mode,
      {bool isDirectory = false, bool recursive = false}) async {
    final sftp = await _sshService.openSftp(host);
    try {
      await chmodWalk(
        path: path,
        isDirectory: isDirectory,
        recursive: recursive,
        setMode: (entryPath) => sftp.setStat(
            entryPath, SftpFileAttrs(mode: SftpFileMode.value(mode))),
        list: (dirPath) async => [
          for (final item in await sftp.listdir(dirPath))
            (name: item.filename, isDirectory: item.attr.isDirectory),
        ],
      );
    } finally {
      sftp.close();
    }
  }

  /// Recursion driver for [chmod], callback-injected for tests (same
  /// pattern as [SftpTransferService.pipeChunks]).
  static Future<void> chmodWalk({
    required String path,
    required bool isDirectory,
    required bool recursive,
    required Future<void> Function(String path) setMode,
    required Future<List<({String name, bool isDirectory})>> Function(
            String path)
        list,
  }) async {
    await setMode(path);
    if (!recursive || !isDirectory) return;
    for (final child in await list(path)) {
      if (child.name == '.' || child.name == '..') continue;
      await chmodWalk(
        path: p.posix.join(path, child.name),
        isDirectory: child.isDirectory,
        recursive: true,
        setMode: setMode,
        list: list,
      );
    }
  }
```

(The file already imports `package:dartssh2/dartssh2.dart` and `package:path/path.dart as p`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/sftp_file_ops_service_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/sftp_file_ops_service.dart app/test/services/sftp_file_ops_service_test.dart
git commit -m "feat: add SftpFileOpsService.chmod with recursive walk"
```

---

### Task 4: `PermissionsDialog` widget

**Files:**
- Create: `app/lib/widgets/permissions_dialog.dart`
- Test: `app/test/widgets/permissions_dialog_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/widgets/permissions_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/permissions_dialog.dart';

Future<({int mode, bool recursive})?> _open(
  WidgetTester tester, {
  required int initialMode,
  bool isDirectory = false,
}) async {
  ({int mode, bool recursive})? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await showDialog<({int mode, bool recursive})>(
            context: context,
            builder: (_) => PermissionsDialog(
              entryName: 'notes.txt',
              initialMode: initialMode,
              isDirectory: isDirectory,
            ),
          );
        },
        child: const Text('go'),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('preloads octal field and checkboxes from initialMode',
      (tester) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    expect(find.widgetWithText(TextField, '644'), findsOneWidget);
    final ownerWrite =
        tester.widget<Checkbox>(find.byKey(const Key('perm_u_w')));
    final otherWrite =
        tester.widget<Checkbox>(find.byKey(const Key('perm_o_w')));
    expect(ownerWrite.value, isTrue);
    expect(otherWrite.value, isFalse);
  });

  testWidgets('toggling a checkbox updates the octal field', (tester) async {
    await _open(tester, initialMode: 0x1A4); // 0o644
    await tester.tap(find.byKey(const Key('perm_u_x')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '744'), findsOneWidget);
  });

  testWidgets('editing the octal field updates the checkboxes',
      (tester) async {
    await _open(tester, initialMode: 0x1A4);
    await tester.enterText(find.byType(TextField), '777');
    await tester.pumpAndSettle();
    final otherWrite =
        tester.widget<Checkbox>(find.byKey(const Key('perm_o_w')));
    expect(otherWrite.value, isTrue);
  });

  testWidgets('Apply returns the edited mode', (tester) async {
    ({int mode, bool recursive})? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<({int mode, bool recursive})>(
              context: context,
              builder: (_) => const PermissionsDialog(
                entryName: 'notes.txt',
                initialMode: 0x1A4,
                isDirectory: false,
              ),
            );
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '755');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result, (mode: 0x1ED, recursive: false));
  });

  testWidgets('recursive checkbox only shown for directories',
      (tester) async {
    await _open(tester, initialMode: 0x1ED, isDirectory: false);
    expect(find.text('Apply recursively'), findsNothing);
    // Dismiss and reopen as directory.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await _open(tester, initialMode: 0x1ED, isDirectory: true);
    expect(find.text('Apply recursively'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/permissions_dialog_test.dart`
Expected: FAIL — package import unresolved.

- [ ] **Step 3: Implement the dialog**

```dart
// app/lib/widgets/permissions_dialog.dart
import 'package:flutter/material.dart';
import '../util/file_mode.dart';

/// chmod dialog: a 9-checkbox rwx grid (owner/group/others) two-way synced
/// with an octal text field. Returns `(mode, recursive)` via Navigator.pop,
/// or null when cancelled. Special bits (setuid/setgid/sticky) survive a
/// checkbox-only edit; the octal field accepts 4-digit values to set them.
class PermissionsDialog extends StatefulWidget {
  final String entryName;
  final int initialMode;
  final bool isDirectory;

  const PermissionsDialog({
    super.key,
    required this.entryName,
    required this.initialMode,
    required this.isDirectory,
  });

  @override
  State<PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<PermissionsDialog> {
  late int _mode = widget.initialMode & 0xFFF;
  late final TextEditingController _octalCtrl =
      TextEditingController(text: modeToOctal(_mode));
  bool _recursive = false;

  static const _fg = Color(0xFFD4D4D4);
  static const _dim = Color(0xFF888888);

  // (row label, read bit, write bit, execute bit) per permission class.
  static const _rows = [
    ('Owner', 0x100, 0x80, 0x40),
    ('Group', 0x20, 0x10, 0x8),
    ('Others', 0x4, 0x2, 0x1),
  ];
  // Key suffixes per row for widget tests: perm_u_r, perm_g_w, perm_o_x...
  static const _rowKeys = ['u', 'g', 'o'];

  void _setBit(int bit, bool on) {
    setState(() {
      _mode = on ? (_mode | bit) : (_mode & ~bit);
      _octalCtrl.text = modeToOctal(_mode);
    });
  }

  void _onOctalChanged(String text) {
    final parsed = parseOctal(text);
    if (parsed == null) return; // keep last valid mode while typing
    setState(() => _mode = parsed);
  }

  @override
  void dispose() {
    _octalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text('Permissions — ${widget.entryName}',
          style: const TextStyle(color: _fg, fontSize: 14)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {0: FixedColumnWidth(64)},
            children: [
              const TableRow(children: [
                SizedBox.shrink(),
                Text('Read',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _dim, fontSize: 11)),
                Text('Write',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _dim, fontSize: 11)),
                Text('Execute',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _dim, fontSize: 11)),
              ]),
              for (final (i, row) in _rows.indexed)
                TableRow(children: [
                  Text(row.$1,
                      style: const TextStyle(color: _fg, fontSize: 12)),
                  for (final (j, bit) in [row.$2, row.$3, row.$4].indexed)
                    Checkbox(
                      key: Key('perm_${_rowKeys[i]}_${'rwx'[j]}'),
                      value: _mode & bit != 0,
                      onChanged: (v) => _setBit(bit, v ?? false),
                      side: const BorderSide(color: Color(0xFF444444)),
                      activeColor: const Color(0xFF22C55E),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Octal', style: TextStyle(color: _dim, fontSize: 12)),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _octalCtrl,
                onChanged: _onOctalChanged,
                style: const TextStyle(
                    color: _fg, fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  isDense: true,
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2A2A2A))),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF22C55E))),
                ),
              ),
            ),
          ]),
          if (widget.isDirectory) ...[
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(
                key: const Key('perm_recursive'),
                value: _recursive,
                onChanged: (v) => setState(() => _recursive = v ?? false),
                side: const BorderSide(color: Color(0xFF444444)),
                activeColor: const Color(0xFF22C55E),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const Text('Apply recursively',
                  style: TextStyle(color: _fg, fontSize: 12)),
            ]),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: _dim)),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (mode: _mode, recursive: _recursive)),
          child:
              const Text('Apply', style: TextStyle(color: Color(0xFF22C55E))),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/permissions_dialog_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/permissions_dialog.dart app/test/widgets/permissions_dialog_test.dart
git commit -m "feat: add chmod permissions dialog (rwx grid + octal field)"
```

---

### Task 5: Shared app-launch helpers

**Files:**
- Create: `app/lib/util/app_launcher.dart`
- Modify: `app/lib/services/external_edit_service.dart` (`_launchWithApp`, ~line 106)
- Modify: `app/lib/widgets/sftp_panel.dart` (`_pickApp`, lines 217–234)

- [ ] **Step 1: Create the helper (extracted from existing code)**

`SftpPanel._pickApp` and `ExternalEditService._launchWithApp` move to a shared util so `LocalFilePanel` can reuse them (Open / Open with… on local files).

```dart
// app/lib/util/app_launcher.dart
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl;

/// Opens [filePath] with the OS default application.
Future<bool> launchFileDefault(String filePath) =>
    launchUrl(Uri.file(filePath));

/// Opens [filePath] with a specific application (`open -a` on macOS, direct
/// process spawn elsewhere). Extracted from ExternalEditService.
Future<bool> launchFileWithApp(String filePath, String appPath) {
  if (Platform.isMacOS) {
    return Process.run('open', ['-a', appPath, filePath])
        .then((r) => r.exitCode == 0);
  }
  if (Platform.isWindows) {
    return Process.run(appPath, [filePath], runInShell: true)
        .then((r) => r.exitCode == 0);
  }
  return Process.run(appPath, [filePath]).then((r) => r.exitCode == 0);
}

/// Lets the user pick an application bundle/executable (per-platform
/// filters). Extracted from SftpPanel._pickApp.
Future<String?> pickApplication() async {
  if (Platform.isMacOS) {
    const typeGroup = XTypeGroup(label: 'Applications', extensions: ['app']);
    final file = await openFile(
        acceptedTypeGroups: [typeGroup], initialDirectory: '/Applications');
    return file?.path;
  }
  if (Platform.isWindows) {
    const typeGroup = XTypeGroup(label: 'Executables', extensions: ['exe']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    return file?.path;
  }
  final file = await openFile();
  return file?.path;
}
```

- [ ] **Step 2: Delegate from the old call sites**

In `app/lib/services/external_edit_service.dart`, add `import '../util/app_launcher.dart';` and replace the `_launchWithApp` body:

```dart
  Future<bool> _launchWithApp(String filePath, String appPath) =>
      launchFileWithApp(filePath, appPath);
```

(Remove the old per-platform branches inside it; keep the method so the injectable `_appLaunch` test seam is untouched.)

In `app/lib/widgets/sftp_panel.dart`, add `import '../util/app_launcher.dart';`, delete the `_pickApp` method (lines 217–234), and replace its one call site (`onChooseApp`, ~line 617) to use `pickApplication()`:

```dart
              final appPath = await pickApplication();
```

The `file_selector` import in `sftp_panel.dart` becomes unused — remove it.

- [ ] **Step 3: Verify**

Run: `cd app && flutter analyze && flutter test test/services/external_edit_service_test.dart`
Expected: No analyzer issues; existing tests PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/util/app_launcher.dart app/lib/services/external_edit_service.dart app/lib/widgets/sftp_panel.dart
git commit -m "refactor: extract shared app-launch helpers to util/app_launcher"
```

---

### Task 6: Generalize the menu into `EntryContextMenu`

**Files:**
- Rename: `app/lib/widgets/sftp_entry_context_menu.dart` → `app/lib/widgets/entry_context_menu.dart`
- Rename test: `app/test/widgets/sftp_entry_context_menu_test.dart` → `app/test/widgets/entry_context_menu_test.dart`
- Modify: `app/lib/widgets/sftp_panel.dart` (import + call site, updated fully in Task 7)

- [ ] **Step 1: git mv both files**

```bash
git mv app/lib/widgets/sftp_entry_context_menu.dart app/lib/widgets/entry_context_menu.dart
git mv app/test/widgets/sftp_entry_context_menu_test.dart app/test/widgets/entry_context_menu_test.dart
```

- [ ] **Step 2: Update the test for the new API and items (failing first)**

Rewrite `app/test/widgets/entry_context_menu_test.dart`. Key changes: widget renamed `EntryContextMenu`; takes `path`/`isDirectory` instead of `entry`; new required callbacks `onRefresh`/`onNewFolder`; new optional `onCopyToTarget`/`copyToTargetDisabledReason`/`onEditPermissions`; folders show **Open** (not Enter); new items present.

```dart
// app/test/widgets/entry_context_menu_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/widgets/entry_context_menu.dart';

const _apps = [
  AppOption(name: 'VS Code', executablePath: '/usr/bin/code', isDefault: true),
  AppOption(name: 'gedit', executablePath: '/usr/bin/gedit', isDefault: false),
];

Widget _wrap({
  required String label,
  required bool isDirectory,
  VoidCallback? onView,
  VoidCallback? onEdit,
  Future<List<AppOption>> Function()? loadApps,
  void Function(AppOption)? onOpenWithApp,
  VoidCallback? onChooseApp,
  VoidCallback? onCopyToTarget,
  String? copyToTargetDisabledReason,
  VoidCallback? onEditPermissions,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EntryContextMenu(
        path: '/home/u/$label',
        isDirectory: isDirectory,
        onOpen: () {},
        onView: onView,
        onEdit: onEdit,
        loadApps: loadApps,
        onOpenWithApp: onOpenWithApp,
        onChooseApp: onChooseApp,
        onCopyToTarget: onCopyToTarget,
        copyToTargetDisabledReason: copyToTargetDisabledReason,
        onRename: () {},
        onDelete: () {},
        onRefresh: () {},
        onNewFolder: () {},
        onEditPermissions: onEditPermissions,
        child: Text(label),
      ),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, String text) async {
  await tester.tap(find.text(text), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('file menu shows all items in order', (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
      onCopyToTarget: () {},
      onEditPermissions: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    for (final item in [
      'Open', 'View', 'Edit', 'Open with', 'Copy to target directory',
      'Rename', 'Delete', 'Refresh', 'New Folder', 'Edit Permissions',
      'Copy path',
    ]) {
      expect(find.text(item), findsOneWidget, reason: 'missing $item');
    }
  });

  testWidgets('directories show Open (not Enter) and no file-only items',
      (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'src',
      isDirectory: true,
      onCopyToTarget: () {},
      onEditPermissions: () {},
    ));
    await _rightClick(tester, 'src');

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Enter'), findsNothing);
    expect(find.text('View'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Open with'), findsNothing);
    expect(find.text('Copy to target directory'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('New Folder'), findsOneWidget);
    expect(find.text('Edit Permissions'), findsOneWidget);
  });

  testWidgets('copy to target disabled with reason', (tester) async {
    var copied = false;
    await tester.pumpWidget(_wrap(
      label: 'src',
      isDirectory: true,
      onCopyToTarget: () => copied = true,
      copyToTargetDisabledReason: 'No target panel',
    ));
    await _rightClick(tester, 'src');

    expect(find.text('No target panel'), findsOneWidget);
    await tester.tap(find.text('Copy to target directory'),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(copied, isFalse);
  });

  testWidgets('copy to target enabled fires callback', (tester) async {
    var copied = false;
    await tester.pumpWidget(_wrap(
      label: 'src',
      isDirectory: true,
      onCopyToTarget: () => copied = true,
    ));
    await _rightClick(tester, 'src');
    await tester.tap(find.text('Copy to target directory'));
    await tester.pumpAndSettle();
    expect(copied, isTrue);
  });

  testWidgets('Edit Permissions hidden when callback is null',
      (tester) async {
    await tester.pumpWidget(_wrap(label: 'src', isDirectory: true));
    await _rightClick(tester, 'src');
    expect(find.text('Edit Permissions'), findsNothing);
  });

  testWidgets('hovering "Open with" opens the submenu without a click',
      (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Open with')));
    await tester.pumpAndSettle();

    expect(find.text('VS Code'), findsOneWidget);
    expect(find.text('gedit'), findsOneWidget);
    expect(find.text('Choose…'), findsOneWidget);
  });

  testWidgets('tapping an app item calls onOpenWithApp', (tester) async {
    AppOption? picked;
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (a) => picked = a,
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VS Code'));
    await tester.pumpAndSettle();
    expect(picked?.executablePath, '/usr/bin/code');
  });

  testWidgets('default app shows a default chip', (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();
    expect(find.text('default'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/entry_context_menu_test.dart`
Expected: FAIL — `EntryContextMenu` not defined.

- [ ] **Step 4: Rewrite the widget**

Replace the contents of `app/lib/widgets/entry_context_menu.dart`:

```dart
// app/lib/widgets/entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_option.dart';

/// Right-click context menu for file/folder entries, shared by the remote
/// SFTP panel and the local file panel. Built on MenuAnchor so the
/// "Open with" entry cascades open on hover like a native menu.
///
/// Layout (│ = divider):
///   File:   Open · View · Edit · Open with ▸ │ Copy to target directory ·
///           Rename · Delete │ Refresh · New Folder · Edit Permissions │
///           Copy path
///   Folder: Open │ same as above
///
/// Optional callbacks hide their item when null, except Copy to target
/// directory which renders disabled with [copyToTargetDisabledReason].
class EntryContextMenu extends StatefulWidget {
  final String path;
  final bool isDirectory;
  final Widget child;

  /// Default action: folders navigate in, files open (editor / OS default).
  final VoidCallback onOpen;
  final VoidCallback? onView;
  final VoidCallback? onEdit;

  /// Fetches the installed-app list for this entry's file type. Called when
  /// the context menu opens; result is cached by AppDiscoveryService.
  final Future<List<AppOption>> Function()? loadApps;
  final void Function(AppOption app)? onOpenWithApp;
  final VoidCallback? onChooseApp;

  /// Copies the entry into the opposite panel's current directory. The item
  /// is disabled (with [copyToTargetDisabledReason] as a hint) when the
  /// transfer is not possible.
  final VoidCallback? onCopyToTarget;
  final String? copyToTargetDisabledReason;

  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  final VoidCallback onNewFolder;

  /// Null hides the item (e.g. local panel on Windows — no chmod).
  final VoidCallback? onEditPermissions;

  const EntryContextMenu({
    super.key,
    required this.path,
    required this.isDirectory,
    required this.child,
    required this.onOpen,
    this.onView,
    this.onEdit,
    this.loadApps,
    this.onOpenWithApp,
    this.onChooseApp,
    this.onCopyToTarget,
    this.copyToTargetDisabledReason,
    required this.onRename,
    required this.onDelete,
    required this.onRefresh,
    required this.onNewFolder,
    this.onEditPermissions,
  });

  @override
  State<EntryContextMenu> createState() => _EntryContextMenuState();
}

class _EntryContextMenuState extends State<EntryContextMenu> {
  final MenuController _controller = MenuController();
  List<AppOption>? _apps; // null = still loading

  static const _fg = Color(0xFFD4D4D4);
  static const _dim = Color(0xFF555555);

  ButtonStyle get _itemStyle => const ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(_fg),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        padding:
            WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        minimumSize: WidgetStatePropertyAll(Size(160, 34)),
        maximumSize: WidgetStatePropertyAll(Size(320, 34)),
        visualDensity: VisualDensity.compact,
      );

  MenuStyle get _menuStyle => MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF1E1E1E)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        )),
      );

  void _openMenu(Offset localPos) {
    if (widget.loadApps != null && _apps == null) {
      widget.loadApps!().then((apps) {
        if (mounted) setState(() => _apps = apps);
      }).catchError((_) {
        if (mounted) setState(() => _apps = const []);
      });
    }
    _controller.open(position: localPos);
  }

  MenuItemButton _item(String label, IconData icon, VoidCallback? onPressed,
      {Color? color}) {
    final c = color ?? _fg;
    return MenuItemButton(
      style: color == null
          ? _itemStyle
          : _itemStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(color)),
      leadingIcon: Icon(icon, size: 14, color: c),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  /// "Copy to target directory" — always listed; disabled with a reason
  /// hint when the transfer matrix cannot move this entry.
  Widget _copyToTargetItem() {
    final reason = widget.copyToTargetDisabledReason;
    final enabled = reason == null && widget.onCopyToTarget != null;
    return MenuItemButton(
      style: enabled
          ? _itemStyle
          : _itemStyle.copyWith(
              foregroundColor: const WidgetStatePropertyAll(_dim),
              maximumSize: const WidgetStatePropertyAll(Size(320, 48)),
            ),
      leadingIcon: Icon(Icons.drive_file_move_outline,
          size: 14, color: enabled ? _fg : _dim),
      onPressed: enabled ? widget.onCopyToTarget : null,
      child: reason == null
          ? const Text('Copy to target directory')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Copy to target directory'),
                Text(reason,
                    style: const TextStyle(fontSize: 10, color: _dim)),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDir = widget.isDirectory;
    return MenuAnchor(
      controller: _controller,
      style: _menuStyle,
      consumeOutsideTap: true,
      menuChildren: [
        _item('Open', isDir ? Icons.folder_open : Icons.open_in_new,
            widget.onOpen),
        if (!isDir && widget.onView != null)
          _item('View', Icons.visibility_outlined, widget.onView),
        if (!isDir && widget.onEdit != null)
          _item('Edit', Icons.edit_outlined, widget.onEdit),
        if (!isDir &&
            (widget.onOpenWithApp != null || widget.onChooseApp != null))
          SubmenuButton(
            style: _itemStyle,
            menuStyle: _menuStyle,
            leadingIcon: const Icon(Icons.apps, size: 14, color: _fg),
            menuChildren: _buildOpenWithChildren(),
            child: const Text('Open with'),
          ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        _copyToTargetItem(),
        _item('Rename', Icons.drive_file_rename_outline, widget.onRename),
        _item('Delete', Icons.delete_outline, widget.onDelete,
            color: const Color(0xFFEF4444)),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        _item('Refresh', Icons.refresh, widget.onRefresh),
        _item('New Folder', Icons.create_new_folder_outlined,
            widget.onNewFolder),
        if (widget.onEditPermissions != null)
          _item('Edit Permissions', Icons.lock_outline,
              widget.onEditPermissions),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        _item('Copy path', Icons.content_copy,
            () => Clipboard.setData(ClipboardData(text: widget.path))),
      ],
      child: GestureDetector(
        onSecondaryTapUp: (d) => _openMenu(d.localPosition),
        child: widget.child,
      ),
    );
  }

  List<Widget> _buildOpenWithChildren() {
    final apps = _apps;
    return [
      if (apps == null)
        MenuItemButton(
          style: _itemStyle.copyWith(
              foregroundColor: const WidgetStatePropertyAll(_dim)),
          onPressed: null,
          child: const Text('Searching apps…'),
        )
      else
        for (final app in apps)
          MenuItemButton(
            style: _itemStyle,
            onPressed: () => widget.onOpenWithApp?.call(app),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(app.name),
                if (app.isDefault) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF22C55E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('default',
                        style: TextStyle(
                            color: Color(0xFF22C55E),
                            fontSize: 9,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
      if (apps == null || apps.isNotEmpty)
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
      MenuItemButton(
        style: _itemStyle,
        leadingIcon:
            const Icon(Icons.folder_open_outlined, size: 14, color: _fg),
        onPressed: widget.onChooseApp,
        child: const Text('Choose…'),
      ),
    ];
  }
}
```

- [ ] **Step 5: Patch `sftp_panel.dart` minimally so it compiles**

(Fully wired in Task 7 — here only rename the import and adapt the call site.)

In `app/lib/widgets/sftp_panel.dart`:
- Change import `'sftp_entry_context_menu.dart'` → `'entry_context_menu.dart'`.
- In `_buildEntryTile`, change `SftpEntryContextMenu(entry: entry, ...)` → `EntryContextMenu(path: entry.path, isDirectory: entry.isDirectory, ...)` and add the two new required callbacks:

```dart
      onRefresh: () => _loadDirectory(prov.currentPath),
      onNewFolder: () => _showNewFolderDialog(prov),
```

- [ ] **Step 6: Run tests**

Run: `cd app && flutter test test/widgets/entry_context_menu_test.dart && flutter analyze`
Expected: PASS (8 tests); no analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add -A app/lib/widgets app/test/widgets
git commit -m "feat: generalize entry context menu with copy-to-target, refresh, new folder, permissions"
```

---

### Task 7: Wire `SftpPanel` (copy-to-target + permissions)

**Files:**
- Modify: `app/lib/widgets/sftp_panel.dart`

- [ ] **Step 1: Add constructor params**

```dart
  /// Copies [entry] into the opposite panel's current directory (wired by
  /// the dual-panel screen). Null when the panel is used standalone.
  final void Function(SftpEntry entry)? onCopyToTarget;

  /// Why copy-to-target is unavailable for [entry] (null = available).
  final String? Function(SftpEntry entry)? copyToTargetBlockReason;
```

Add `this.onCopyToTarget, this.copyToTargetBlockReason,` to the constructor.

- [ ] **Step 2: Wire the menu in `_buildEntryTile`**

```dart
    return EntryContextMenu(
      path: entry.path,
      isDirectory: entry.isDirectory,
      onOpen: () => _onEntryTap(entry),
      onView: entry.isDirectory ? null : () => _openViewer(entry),
      onEdit: entry.isDirectory ? null : () => _openEditor(entry),
      loadApps: /* unchanged */,
      onOpenWithApp: /* unchanged */,
      onChooseApp: /* unchanged */,
      onCopyToTarget: widget.onCopyToTarget == null
          ? null
          : () => widget.onCopyToTarget!(entry),
      copyToTargetDisabledReason: widget.onCopyToTarget == null
          ? 'No target panel'
          : widget.copyToTargetBlockReason?.call(entry),
      onRename: () => _showRenameDialog(prov, entry),
      onDelete: () => _showDeleteConfirm(prov, [entry]),
      onRefresh: () => _loadDirectory(prov.currentPath),
      onNewFolder: () => _showNewFolderDialog(prov),
      onEditPermissions: () => _showPermissionsDialog(prov, entry),
      child: /* unchanged Draggable */
```

- [ ] **Step 3: Add `_showPermissionsDialog`**

Add `import 'permissions_dialog.dart';` and `import '../util/file_mode.dart';` (for `modeToOctal` in the snackbar message), then:

```dart
  Future<void> _showPermissionsDialog(
      SftpPanelProvider prov, SftpEntry entry) async {
    final result = await showDialog<({int mode, bool recursive})>(
      context: context,
      builder: (_) => PermissionsDialog(
        entryName: entry.name,
        initialMode: entry.mode ?? 0,
        isDirectory: entry.isDirectory,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<SftpFileOpsService>().chmod(
            widget.host!,
            entry.path,
            result.mode,
            isDirectory: entry.isDirectory,
            recursive: result.recursive,
          );
      _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('chmod ${modeToOctal(result.mode)} failed: $e'),
            backgroundColor: const Color(0xFF2A1A1A)));
      }
    }
  }
```

- [ ] **Step 4: Verify**

Run: `cd app && flutter analyze && flutter test test/widgets/sftp_panel_history_nav_test.dart test/widgets/sftp_panel_initial_path_test.dart`
Expected: No analyzer issues; existing panel tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart
git commit -m "feat: wire copy-to-target and edit-permissions into remote SFTP panel"
```

---

### Task 8: Wire `LocalFilePanel` to the shared menu

**Files:**
- Modify: `app/lib/widgets/local_file_panel.dart`

- [ ] **Step 1: Add imports and constructor params**

Imports to add:

```dart
import '../models/app_option.dart';
import '../services/app_discovery_service.dart';
import '../util/app_launcher.dart';
import '../util/file_mode.dart';
import 'entry_context_menu.dart';
import 'permissions_dialog.dart';
```

Constructor params (mirroring SftpPanel):

```dart
  /// Copies [entry] into the opposite panel's current directory (wired by
  /// the dual-panel screen). Null when the panel is used standalone.
  final void Function(LocalEntry entry)? onCopyToTarget;

  /// Why copy-to-target is unavailable for [entry] (null = available).
  final String? Function(LocalEntry entry)? copyToTargetBlockReason;
```

- [ ] **Step 2: Refactor rename/delete to entry-based helpers**

Replace `_renameSelected` / `_deleteSelected` bodies so both the header Actions menu (selection-based) and the context menu (clicked entry) share them:

```dart
  Future<void> _renameSelected() async {
    final selected = widget.provider.selectedEntries;
    if (selected.length != 1) return;
    await _rename(selected.first);
  }

  Future<void> _rename(LocalEntry entry) async {
    final newName = await _showInputDialog(
      context,
      title: 'Rename',
      hint: 'New name',
      initial: entry.name,
    );
    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == entry.name) {
      return;
    }
    final newPath = p.join(p.dirname(entry.path), newName.trim());
    try {
      if (entry.isDirectory) {
        await Directory(entry.path).rename(newPath);
      } else {
        await File(entry.path).rename(newPath);
      }
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('Rename failed: $e');
    }
  }

  Future<void> _deleteSelected() =>
      _delete(widget.provider.selectedEntries.toList());

  Future<void> _delete(List<LocalEntry> entries) async {
    if (entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      // ... existing dialog unchanged, but use entries.length ...
    );
    if (confirmed != true) return;
    try {
      for (final entry in entries) {
        if (entry.isDirectory) {
          await Directory(entry.path).delete(recursive: true);
        } else {
          await File(entry.path).delete();
        }
      }
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('Delete failed: $e');
    }
  }
```

- [ ] **Step 3: Add open / open-with / permissions actions**

```dart
  Future<void> _openEntry(LocalEntry entry) async {
    if (entry.isDirectory) {
      widget.provider.loadDirectory(entry.path);
      return;
    }
    final ok = await launchFileDefault(entry.path);
    if (!ok && mounted) _showError('Could not open ${entry.name}');
  }

  Future<void> _openWith(LocalEntry entry, String appPath) async {
    final ok = await launchFileWithApp(entry.path, appPath);
    if (!ok && mounted) _showError('Open with failed for ${entry.name}');
  }

  Future<void> _showPermissionsDialog(LocalEntry entry) async {
    final stat = FileStat.statSync(entry.path);
    final result = await showDialog<({int mode, bool recursive})>(
      context: context,
      builder: (_) => PermissionsDialog(
        entryName: entry.name,
        initialMode: stat.mode,
        isDirectory: entry.isDirectory,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await chmodLocal(entry.path, result.mode, recursive: result.recursive);
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('chmod failed: $e');
    }
  }
```

- [ ] **Step 4: Replace `showMenu` with the shared widget**

Delete `_showContextMenu` and `_contextItem`. In the `ListView.builder` item builder, wrap the row and drop the row-level secondary-tap handler:

```dart
              return EntryContextMenu(
                path: entry.path,
                isDirectory: entry.isDirectory,
                onOpen: () => _openEntry(entry),
                loadApps: entry.isDirectory
                    ? null
                    : () => context
                        .read<AppDiscoveryService>()
                        .getAppsFor(entry.path),
                onOpenWithApp: entry.isDirectory
                    ? null
                    : (app) => _openWith(entry, app.executablePath),
                onChooseApp: entry.isDirectory
                    ? null
                    : () async {
                        final appPath = await pickApplication();
                        if (appPath != null && mounted) {
                          await _openWith(entry, appPath);
                        }
                      },
                onCopyToTarget: widget.onCopyToTarget == null
                    ? null
                    : () => widget.onCopyToTarget!(entry),
                copyToTargetDisabledReason: widget.onCopyToTarget == null
                    ? 'No target panel'
                    : widget.copyToTargetBlockReason?.call(entry),
                onRename: () => _rename(entry),
                onDelete: () => _delete([entry]),
                onRefresh: () => widget.provider.reload(),
                onNewFolder: _createFolder,
                onEditPermissions: Platform.isWindows
                    ? null
                    : () => _showPermissionsDialog(entry),
                child: _LocalEntryRow(
                  entry: entry,
                  selected: prov.selectedEntries.contains(entry),
                  onToggleSelect: () => prov.toggleSelection(entry),
                  onTap: /* unchanged */,
                  onDoubleTap: /* unchanged */,
                ),
              );
```

In `_LocalEntryRow`, remove the `onSecondaryTap` field/param and the `onSecondaryTapUp:` line in its `GestureDetector` (the wrapping `EntryContextMenu` now owns right-click). View/Edit are intentionally null — local files open via the OS, matching the previous local panel behavior.

Note: `AppDiscoveryService` is provided by `DualPanelSftpScreen`'s MultiProvider, the only place `LocalFilePanel` is mounted.

- [ ] **Step 5: Verify**

Run: `cd app && flutter analyze && flutter test test/widgets/local_file_panel_checkbox_test.dart test/widgets/dual_panel_sftp_screen_test.dart test/widgets/dual_panel_breadcrumb_repro_test.dart`
Expected: No analyzer issues; existing tests PASS. If `local_file_panel_checkbox_test.dart` pumps `LocalFilePanel` without an `AppDiscoveryService` provider it still passes — the service is only read lazily inside `loadApps` when the menu opens on a file.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/local_file_panel.dart
git commit -m "feat: use shared context menu in local file panel (open, open with, chmod)"
```

---

### Task 9: Wire `DualPanelSftpScreen` copy-to-target

**Files:**
- Modify: `app/lib/widgets/dual_panel_sftp_screen.dart` (`_slot`, ~line 409)

- [ ] **Step 1: Add the block-reason resolver**

```dart
  /// Why a context-menu copy-to-target from [fromLeft] cannot run for an
  /// entry of [isDirectory] (null = it can). Mirrors the transfer matrix:
  /// remote→remote relays are file-only.
  String? _copyBlockReason(bool fromLeft, {required bool isDirectory}) {
    final src = _sourceOf(fromLeft);
    final dst = _sourceOf(!fromLeft);
    if (src == null || dst == null) return 'No target panel';
    if (isDirectory &&
        transferKindFor(src, dst) == TransferKind.remoteRelay) {
      return 'Folders not supported between two remote hosts';
    }
    return null;
  }
```

- [ ] **Step 2: Pass callbacks in `_slot`**

```dart
    if (src is LocalSource) {
      panel = LocalFilePanel(
        provider: _localOf(left),
        onChangeSource: () => _pickSource(left),
        onCopyToTarget: (entry) =>
            _transfer(fromLeft: left, localEntries: [entry]),
        copyToTargetBlockReason: (entry) =>
            _copyBlockReason(left, isDirectory: entry.isDirectory),
      );
    } else {
      final host = src is HostSource ? src.host : null;
      panel = SftpPanel(
        key: ValueKey('${left ? 'l' : 'r'}_${host?.id}'),
        host: host,
        panelId: left ? 'remote_left' : 'remote_right',
        provider: _sftpOf(left),
        onChangeHost: () => _pickSource(left),
        initialPath:
            host == null ? '/' : (_remotePathByHost[host.id] ?? '/'),
        onCopyToTarget: (entry) =>
            _transfer(fromLeft: left, sftpEntries: [entry]),
        copyToTargetBlockReason: (entry) =>
            _copyBlockReason(left, isDirectory: entry.isDirectory),
      );
    }
```

- [ ] **Step 3: Verify**

Run: `cd app && flutter analyze && flutter test test/widgets/dual_panel_sftp_screen_test.dart`
Expected: No analyzer issues; tests PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/dual_panel_sftp_screen.dart
git commit -m "feat: wire context-menu copy-to-target through dual-panel transfer matrix"
```

---

### Task 10: Full verification + changelog

**Files:**
- Modify: `CHANGELOG.md` ([Unreleased] section)

- [ ] **Step 1: Run the full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: No analyzer issues; all tests PASS. Fix any regressions before proceeding.

- [ ] **Step 2: Update CHANGELOG.md**

Under `[Unreleased]` → `### Added` (create the section if missing):

```markdown
- Unified right-click context menu in both SFTP panels: Open, Open with…,
  Copy to target directory, Rename, Delete, Refresh, New Folder, and
  Edit Permissions (chmod with rwx grid, octal field, and recursive apply)
```

- [ ] **Step 3: Smoke test (manual)**

Run: `cd app && flutter run -d macos`
Check: right-click a remote file/folder and a local file/folder — items match the spec; Copy to target directory is dimmed with a reason when the other slot is empty; Edit Permissions round-trips a mode change.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entry for unified entry context menu"
```
