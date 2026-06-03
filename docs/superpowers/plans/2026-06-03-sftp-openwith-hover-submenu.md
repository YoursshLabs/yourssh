# SFTP "Open with" Hover Submenu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the click-to-open second menu for "Open with" with a hover-opening cascading submenu using Flutter's `MenuAnchor` + `SubmenuButton`.

**Architecture:** `SftpEntryContextMenu` becomes a StatefulWidget wrapping its child in a `MenuAnchor`; right-click opens the menu at the cursor via `MenuController.open(position:)`. "Open with" is a `SubmenuButton` (hover-opens on desktop). The app list loads asynchronously when the menu opens and is swapped in via `setState`. `sftp_panel.dart` drops its second-`showMenu` flow and passes `loadApps` / `onOpenWithApp` / `onChooseApp` callbacks instead.

**Tech Stack:** Flutter Material 3 menus (`MenuAnchor`, `MenuItemButton`, `SubmenuButton`), existing `AppDiscoveryService` + `ExternalEditService`.

**Spec:** `docs/superpowers/specs/2026-06-03-sftp-openwith-hover-submenu-design.md`

---

### Task 1: Rewrite `SftpEntryContextMenu` with MenuAnchor (TDD)

**Files:**
- Modify: `app/lib/widgets/sftp_entry_context_menu.dart` (full rewrite)
- Modify: `app/test/widgets/sftp_entry_context_menu_test.dart` (full rewrite)

- [ ] **Step 1: Write the failing tests**

Replace `app/test/widgets/sftp_entry_context_menu_test.dart` with:

```dart
// app/test/widgets/sftp_entry_context_menu_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/widgets/sftp_entry_context_menu.dart';

final _file = SftpEntry(
  name: 'notes.txt',
  path: '/home/u/notes.txt',
  isDirectory: false,
  size: 10,
  modifiedAt: DateTime(2026),
);

final _dir = SftpEntry(
  name: 'src',
  path: '/home/u/src',
  isDirectory: true,
  size: 0,
  modifiedAt: DateTime(2026),
);

const _apps = [
  AppOption(name: 'VS Code', executablePath: '/usr/bin/code', isDefault: true),
  AppOption(name: 'gedit', executablePath: '/usr/bin/gedit', isDefault: false),
];

Widget _wrap({
  required SftpEntry entry,
  VoidCallback? onView,
  VoidCallback? onEdit,
  Future<List<AppOption>> Function()? loadApps,
  void Function(AppOption)? onOpenWithApp,
  VoidCallback? onChooseApp,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SftpEntryContextMenu(
        entry: entry,
        onOpen: () {},
        onView: onView,
        onEdit: onEdit,
        loadApps: loadApps,
        onOpenWithApp: onOpenWithApp,
        onChooseApp: onChooseApp,
        onRename: () {},
        onDelete: () {},
        child: Text(entry.name),
      ),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, String text) async {
  await tester.tap(find.text(text), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right-click shows View, Edit, Open with for files',
      (tester) async {
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    expect(find.text('View'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Open with'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
  });

  testWidgets('directories show Enter and no Open with', (tester) async {
    await tester.pumpWidget(_wrap(entry: _dir));
    await _rightClick(tester, 'src');

    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('View'), findsNothing);
    expect(find.text('Open with'), findsNothing);
  });

  testWidgets('hovering "Open with" opens the submenu without a click',
      (tester) async {
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    // Simulate a mouse hover over the "Open with" submenu button.
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
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
      entry: _file,
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

  testWidgets('tapping Choose… calls onChooseApp', (tester) async {
    var chooseCalled = false;
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () => chooseCalled = true,
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();

    expect(chooseCalled, isTrue);
  });

  testWidgets('tapping View calls onView', (tester) async {
    var viewCalled = false;
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () => viewCalled = true,
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(viewCalled, isTrue);
  });

  testWidgets('default app shows a default chip', (tester) async {
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();

    expect(find.text('default'), findsOneWidget); // VS Code is default
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd app && flutter test test/widgets/sftp_entry_context_menu_test.dart`
Expected: FAIL — `No named parameter with the name 'loadApps'` (compile error).

- [ ] **Step 3: Rewrite the widget**

Replace `app/lib/widgets/sftp_entry_context_menu.dart` with:

```dart
// app/lib/widgets/sftp_entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_option.dart';
import '../models/sftp_entry.dart';

/// Right-click context menu for SFTP entries, built on MenuAnchor so the
/// "Open with" entry cascades open on hover like a native menu.
class SftpEntryContextMenu extends StatefulWidget {
  final SftpEntry entry;
  final Widget child;
  // Directories use onOpen (Enter); files use the split callbacks below.
  final VoidCallback onOpen;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  /// Fetches the installed-app list for this entry's file type. Called when
  /// the context menu opens; result is cached by AppDiscoveryService.
  final Future<List<AppOption>> Function()? loadApps;
  final void Function(AppOption app)? onOpenWithApp;
  final VoidCallback? onChooseApp;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const SftpEntryContextMenu({
    super.key,
    required this.entry,
    required this.child,
    required this.onOpen,
    this.onView,
    this.onEdit,
    this.loadApps,
    this.onOpenWithApp,
    this.onChooseApp,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<SftpEntryContextMenu> createState() => _SftpEntryContextMenuState();
}

class _SftpEntryContextMenuState extends State<SftpEntryContextMenu> {
  final MenuController _controller = MenuController();
  List<AppOption>? _apps; // null = still loading

  static const _fg = Color(0xFFD4D4D4);
  static const _dim = Color(0xFF555555);

  ButtonStyle get _itemStyle => ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(_fg),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12)),
        minimumSize: const WidgetStatePropertyAll(Size(160, 34)),
        maximumSize: const WidgetStatePropertyAll(Size(320, 34)),
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

  @override
  Widget build(BuildContext context) {
    final isDir = widget.entry.isDirectory;
    return MenuAnchor(
      controller: _controller,
      style: _menuStyle,
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          style: _itemStyle,
          leadingIcon: Icon(
              isDir ? Icons.folder_open : Icons.visibility_outlined,
              size: 14, color: _fg),
          onPressed: isDir ? widget.onOpen : widget.onView,
          child: Text(isDir ? 'Enter' : 'View'),
        ),
        if (!isDir && widget.onEdit != null)
          MenuItemButton(
            style: _itemStyle,
            leadingIcon: const Icon(Icons.edit_outlined, size: 14, color: _fg),
            onPressed: widget.onEdit,
            child: const Text('Edit'),
          ),
        if (!isDir && (widget.onOpenWithApp != null || widget.onChooseApp != null))
          SubmenuButton(
            style: _itemStyle,
            menuStyle: _menuStyle,
            leadingIcon: const Icon(Icons.apps, size: 14, color: _fg),
            menuChildren: _buildOpenWithChildren(),
            child: const Text('Open with'),
          ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        MenuItemButton(
          style: _itemStyle,
          leadingIcon: const Icon(Icons.drive_file_rename_outline,
              size: 14, color: _fg),
          onPressed: widget.onRename,
          child: const Text('Rename'),
        ),
        MenuItemButton(
          style: _itemStyle.copyWith(
              foregroundColor:
                  const WidgetStatePropertyAll(Color(0xFFEF4444))),
          leadingIcon: const Icon(Icons.delete_outline,
              size: 14, color: Color(0xFFEF4444)),
          onPressed: widget.onDelete,
          child: const Text('Delete'),
        ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        MenuItemButton(
          style: _itemStyle,
          leadingIcon: const Icon(Icons.content_copy, size: 14, color: _fg),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: widget.entry.path)),
          child: const Text('Copy path'),
        ),
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
                      color: const Color(0xFF22C55E).withValues(alpha: 0.15),
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

- [ ] **Step 4: Run to verify pass**

Run: `cd app && flutter test test/widgets/sftp_entry_context_menu_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/sftp_entry_context_menu.dart app/test/widgets/sftp_entry_context_menu_test.dart
git commit -m "feat(sftp): MenuAnchor context menu with hover-opening Open-with submenu"
```

---

### Task 2: Rewire `sftp_panel.dart`

**Files:**
- Modify: `app/lib/widgets/sftp_panel.dart`

No new test file — covered by analyzer + full suite (the menu behavior itself is tested in Task 1).

- [ ] **Step 1: Delete the second-menu flow**

Remove from `sftp_panel.dart`:
- the entire `_showOpenWithSubmenu` method
- the `_OpenWithChoice` class at the bottom of the file

- [ ] **Step 2: Add the launch helper and rewire callbacks**

`_openWithApp` already exists with signature `(SftpEntry, String appPath, ExternalEditService, ScaffoldMessengerState)`. Simplify it to read dependencies itself:

```dart
  Future<void> _openWithApp(SftpEntry entry, String appPath) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<ExternalEditService>();
    _wireExternalCallbacks(service, messenger);
    try {
      await service.openExternalWith(widget.host!, entry, appPath);
      messenger.showSnackBar(SnackBar(
          content: Text('Opened ${entry.name} — watching for changes'),
          duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Open with failed: $e'),
          backgroundColor: const Color(0xFF2A1A1A)));
    }
  }
```

In `_buildEntryTile`, replace the `onOpenWith` wiring with:

```dart
      loadApps: entry.isDirectory
          ? null
          : () {
              final stub =
                  '/tmp/stub${entry.extension.isEmpty ? '' : '.${entry.extension}'}';
              return context.read<AppDiscoveryService>().getAppsFor(stub);
            },
      onOpenWithApp: entry.isDirectory
          ? null
          : (app) => _openWithApp(entry, app.executablePath),
      onChooseApp: entry.isDirectory
          ? null
          : () async {
              final appPath = await _pickApp();
              if (appPath != null && mounted) {
                await _openWithApp(entry, appPath);
              }
            },
```

Keep `_pickApp()` and `_wireExternalCallbacks()` unchanged. Remove the now-unused `import '../models/app_option.dart';` only if the file no longer references `AppOption` (the `loadApps` closure returns it implicitly, so the import may still be needed — keep if analyzer requires).

- [ ] **Step 3: Analyze + run full suite**

Run: `cd app && flutter analyze && flutter test`
Expected: analyzer clean (project files), all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart
git commit -m "feat(sftp): wire hover submenu callbacks in SFTP panel"
```

---

### Task 3: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update the existing Unreleased "Open with…" entry**

Amend the existing bullet to mention hover (replace "submenu that lists" sentence start):

The entry should read: "**Open with… (SFTP)** — replaces "Open with external app" with an **Open with ▶** submenu that **opens on hover** and lists every application installed on your machine that can open the file's type …" (rest unchanged).

- [ ] **Step 2: Run analyzer + tests one final time, then commit**

Run: `cd app && flutter analyze && flutter test`

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): hover-opening Open-with submenu"
```

---

## Self-Review Notes

- **Spec coverage:** MenuAnchor rewrite ✅ Task 1; async app loading with "Searching apps…" ✅ Task 1 widget; hover test ✅ Task 1 tests; panel rewiring + `_showOpenWithSubmenu` removal ✅ Task 2; changelog ✅ Task 3.
- **Type consistency:** `loadApps: Future<List<AppOption>> Function()?`, `onOpenWithApp: void Function(AppOption)?`, `onChooseApp: VoidCallback?` consistent between widget (Task 1) and panel wiring (Task 2). `_openWithApp(SftpEntry, String)` simplified signature used by both `onOpenWithApp` and `onChooseApp`.
- **Note:** old `onOpenWith(Offset)` param is fully removed; the only caller is `sftp_panel.dart`, updated in Task 2.
