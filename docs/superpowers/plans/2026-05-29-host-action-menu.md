# Host Action Menu — Extended Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four new actions to the per-host right-click menu: Duplicate (opens edit panel), Copy SSH URL (clipboard), Move to Group (dialog picker), Export (ssh/config or JSON).

**Architecture:** All changes are confined to `app/lib/widgets/hosts_dashboard.dart`. Two new private widget classes (`_MoveToGroupDialog`, `_ExportDialog`) are added at the bottom of the file. No provider, model, or service changes required.

**Tech Stack:** Flutter (Dart), `package:flutter/services.dart` (Clipboard), `package:provider/provider.dart` (existing), `package:uuid/uuid.dart` (existing via Host model).

---

## File Map

| File | Change |
|------|--------|
| `app/lib/widgets/hosts_dashboard.dart` | Add import, 4 menu items, 2 private dialog widgets |
| `app/test/widgets/hosts_dashboard_menu_test.dart` | New — unit/widget tests for menu logic |

---

### Task 1: Add `package:flutter/services.dart` import and Copy SSH URL action

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart:1-10` (imports)
- Modify: `app/lib/widgets/hosts_dashboard.dart:431-438` (`_showMenu` items)
- Create: `app/test/widgets/hosts_dashboard_menu_test.dart`

- [ ] **Step 1: Create test file and write failing test**

Create `app/test/widgets/hosts_dashboard_menu_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Copy SSH URL formatting', () {
    test('formats standard port correctly', () {
      final host = Host(label: 'Test', host: 'example.com', port: 22, username: 'admin');
      final url = 'ssh://${host.username}@${host.host}:${host.port}';
      expect(url, 'ssh://admin@example.com:22');
    });

    test('formats non-standard port correctly', () {
      final host = Host(label: 'Test', host: '10.0.0.1', port: 2222, username: 'root');
      final url = 'ssh://${host.username}@${host.host}:${host.port}';
      expect(url, 'ssh://root@10.0.0.1:2222');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it passes (pure string logic, no mocking needed)**

```bash
cd app && flutter test test/widgets/hosts_dashboard_menu_test.dart
```

Expected: PASS (string formatting is trivial — this validates the format spec)

- [ ] **Step 3: Add the import to `hosts_dashboard.dart`**

In `app/lib/widgets/hosts_dashboard.dart`, add after line 3 (`import 'package:flutter/material.dart';`):

```dart
import 'package:flutter/services.dart';
```

- [ ] **Step 4: Add Copy SSH URL menu item to `_showMenu`**

In `_showMenu` (around line 431), replace the existing items block:

```dart
items: <PopupMenuEntry<String>>[
  _menuItem('terminal', Icons.terminal, 'Connect', () => sessionProvider.connect(widget.host)),
  _menuItem('sftp', Icons.folder_outlined, 'SFTP', () => _openSftp(context)),
  _menuItem('edit', Icons.edit_outlined, 'Edit', () => widget.onEditHost?.call(widget.host)),
  const PopupMenuDivider(),
  _menuItem('duplicate', Icons.copy_outlined, 'Duplicate', () => _duplicate(context, hostProvider)),
  _menuItem('copy_url', Icons.link_outlined, 'Copy SSH URL', () => _copySshUrl(context)),
  _menuItem('move_group', Icons.drive_file_move_outlined, 'Move to Group', () => _moveToGroup(context, hostProvider)),
  _menuItem('export', Icons.upload_outlined, 'Export', () => _export(context)),
  const PopupMenuDivider(),
  _menuItem('delete', Icons.delete_outlined, 'Delete', () => hostProvider.deleteHost(widget.host.id), color: AppColors.red),
],
```

- [ ] **Step 5: Add `_copySshUrl` method to `_HostCardState`**

Add this method after `_openSftp`:

```dart
void _copySshUrl(BuildContext context) {
  final url = 'ssh://${widget.host.username}@${widget.host.host}:${widget.host.port}';
  Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('SSH URL copied'), duration: Duration(seconds: 2)),
  );
}
```

- [ ] **Step 6: Add placeholder stubs for the other three methods (so the app compiles)**

Add after `_copySshUrl`:

```dart
void _duplicate(BuildContext context, HostProvider hostProvider) {}
void _moveToGroup(BuildContext context, HostProvider hostProvider) {}
void _export(BuildContext context) {}
```

- [ ] **Step 7: Run the app to verify the menu shows and Copy SSH URL works**

```bash
cd app && flutter run -d macos
```

Right-click a host card → verify 9 menu items appear → tap "Copy SSH URL" → verify SnackBar shows.

- [ ] **Step 8: Commit**

```bash
cd app && git add lib/widgets/hosts_dashboard.dart test/widgets/hosts_dashboard_menu_test.dart
git commit -m "feat: add Copy SSH URL action to host menu"
```

---

### Task 2: Implement Duplicate action

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (`_duplicate` method stub)
- Modify: `app/test/widgets/hosts_dashboard_menu_test.dart` (add duplicate tests)

- [ ] **Step 1: Add duplicate logic tests**

Add to `hosts_dashboard_menu_test.dart` inside `main()`:

```dart
group('Duplicate host', () {
  test('copy has different id', () {
    final original = Host(label: 'Prod', host: '1.2.3.4', port: 22, username: 'root');
    final copy = Host(
      label: '${original.label} (copy)',
      host: original.host,
      port: original.port,
      username: original.username,
      authType: original.authType,
      keyId: original.keyId,
      group: original.group,
    );
    expect(copy.id, isNot(original.id));
    expect(copy.label, 'Prod (copy)');
    expect(copy.host, original.host);
    expect(copy.group, original.group);
  });
});
```

- [ ] **Step 2: Run to verify test passes**

```bash
cd app && flutter test test/widgets/hosts_dashboard_menu_test.dart
```

Expected: PASS

- [ ] **Step 3: Replace `_duplicate` stub with real implementation**

Replace the stub in `_HostCardState`:

```dart
Future<void> _duplicate(BuildContext context, HostProvider hostProvider) async {
  final copy = Host(
    label: '${widget.host.label} (copy)',
    host: widget.host.host,
    port: widget.host.port,
    username: widget.host.username,
    authType: widget.host.authType,
    keyId: widget.host.keyId,
    group: widget.host.group,
  );
  await hostProvider.addHost(copy);
  if (!context.mounted) return;
  widget.onEditHost?.call(copy);
}
```

- [ ] **Step 4: Run the app and verify**

```bash
cd app && flutter run -d macos
```

Right-click a host → tap "Duplicate" → verify the edit panel opens with label ending in `" (copy)"` → verify canceling still leaves the duplicate in the list.

- [ ] **Step 5: Commit**

```bash
cd app && git add lib/widgets/hosts_dashboard.dart test/widgets/hosts_dashboard_menu_test.dart
git commit -m "feat: add Duplicate action to host menu"
```

---

### Task 3: Implement Move to Group dialog

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (`_moveToGroup` stub → real impl + `_MoveToGroupDialog` class)
- Modify: `app/test/widgets/hosts_dashboard_menu_test.dart` (add group-list tests)

- [ ] **Step 1: Add group-derivation logic tests**

Add to `hosts_dashboard_menu_test.dart`:

```dart
group('Move to Group — group list', () {
  test('derives distinct non-empty groups from host list', () {
    final hosts = [
      Host(label: 'A', host: 'a.com', port: 22, username: 'u', group: 'production'),
      Host(label: 'B', host: 'b.com', port: 22, username: 'u', group: 'staging'),
      Host(label: 'C', host: 'c.com', port: 22, username: 'u', group: 'production'),
      Host(label: 'D', host: 'd.com', port: 22, username: 'u', group: ''),
    ];
    final groups = hosts
        .map((h) => h.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    expect(groups, ['production', 'staging']);
  });

  test('returns empty list when all hosts have no group', () {
    final hosts = [
      Host(label: 'A', host: 'a.com', port: 22, username: 'u'),
    ];
    final groups = hosts
        .map((h) => h.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    expect(groups, isEmpty);
  });
});
```

- [ ] **Step 2: Run to verify tests pass**

```bash
cd app && flutter test test/widgets/hosts_dashboard_menu_test.dart
```

Expected: PASS

- [ ] **Step 3: Add `_MoveToGroupDialog` widget at the bottom of `hosts_dashboard.dart`** (before the final `}`)

```dart
// ── Move to Group Dialog ──────────────────────────────────

class _MoveToGroupDialog extends StatelessWidget {
  final Host host;
  final List<String> groups;
  final void Function(String) onSelect;

  const _MoveToGroupDialog({
    required this.host,
    required this.groups,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final options = ['', ...groups]; // '' = No group
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Move to Group', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 280,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (_, i) {
            final g = options[i];
            final label = g.isEmpty ? 'No group' : g;
            final isCurrent = g == host.group;
            return ListTile(
              dense: true,
              title: Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              trailing: isCurrent ? const Icon(Icons.check, size: 16, color: AppColors.textSecondary) : null,
              onTap: () {
                Navigator.of(context).pop();
                onSelect(g);
              },
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace `_moveToGroup` stub with real implementation**

```dart
void _moveToGroup(BuildContext context, HostProvider hostProvider) {
  final groups = hostProvider.allHosts
      .map((h) => h.group)
      .where((g) => g.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  showDialog<void>(
    context: context,
    builder: (_) => _MoveToGroupDialog(
      host: widget.host,
      groups: groups,
      onSelect: (g) => hostProvider.updateHost(widget.host.copyWith(group: g)),
    ),
  );
}
```

- [ ] **Step 5: Update `Host.copyWith` to support clearing group to empty string**

Open `app/lib/models/host.dart`. The current `copyWith` signature is:

```dart
Host copyWith({
  String? label,
  String? host,
  int? port,
  String? username,
  AuthType? authType,
  String? keyId,
  String? group,
})
```

This already supports `group: ''` — passing an empty string works because Dart uses `??` operator. Verify: `group: group ?? this.group` — yes, passing `''` will set group to `''`. No change needed.

- [ ] **Step 6: Run the app and verify**

```bash
cd app && flutter run -d macos
```

Right-click a host → tap "Move to Group" → dialog appears with group list → current group has checkmark → selecting a group updates the host's card immediately.

- [ ] **Step 7: Commit**

```bash
cd app && git add lib/widgets/hosts_dashboard.dart test/widgets/hosts_dashboard_menu_test.dart
git commit -m "feat: add Move to Group action to host menu"
```

---

### Task 4: Implement Export dialog

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (`_export` stub → real impl + `_ExportDialog` class)

- [ ] **Step 1: Add export format generation tests**

Add to `hosts_dashboard_menu_test.dart`:

```dart
group('Export formats', () {
  late Host host;

  setUp(() {
    host = Host(
      label: 'My Server',
      host: '192.168.1.10',
      port: 2222,
      username: 'deploy',
      group: 'prod',
    );
  });

  test('ssh/config format', () {
    final output = 'Host ${host.label}\n'
        '    HostName ${host.host}\n'
        '    User ${host.username}\n'
        '    Port ${host.port}';
    expect(output, contains('Host My Server'));
    expect(output, contains('HostName 192.168.1.10'));
    expect(output, contains('User deploy'));
    expect(output, contains('Port 2222'));
  });

  test('json export excludes id and createdAt', () {
    final json = {
      'label': host.label,
      'host': host.host,
      'port': host.port,
      'username': host.username,
      'authType': host.authType.name,
      'group': host.group,
      'tags': host.tags,
    };
    expect(json.containsKey('id'), isFalse);
    expect(json.containsKey('createdAt'), isFalse);
    expect(json['label'], 'My Server');
  });
});
```

- [ ] **Step 2: Run to verify tests pass**

```bash
cd app && flutter test test/widgets/hosts_dashboard_menu_test.dart
```

Expected: PASS

- [ ] **Step 3: Add `_ExportDialog` widget at the bottom of `hosts_dashboard.dart`**

```dart
// ── Export Dialog ─────────────────────────────────────────

class _ExportDialog extends StatefulWidget {
  final Host host;
  const _ExportDialog({required this.host});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _showSshConfig = true;

  String get _sshConfigText =>
      'Host ${widget.host.label}\n'
      '    HostName ${widget.host.host}\n'
      '    User ${widget.host.username}\n'
      '    Port ${widget.host.port}';

  String get _jsonText {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'label': widget.host.label,
      'host': widget.host.host,
      'port': widget.host.port,
      'username': widget.host.username,
      'authType': widget.host.authType.name,
      'group': widget.host.group,
      'tags': widget.host.tags,
    });
  }

  String get _currentText => _showSshConfig ? _sshConfigText : _jsonText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Export Host', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _formatTab('.ssh/config', selected: _showSshConfig, onTap: () => setState(() => _showSshConfig = true)),
                const SizedBox(width: 8),
                _formatTab('JSON', selected: !_showSshConfig, onTap: () => setState(() => _showSshConfig = false)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                _currentText,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _currentText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
            );
          },
          child: const Text('Copy', style: TextStyle(color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  Widget _formatTab(String label, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.textPrimary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? AppColors.border : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Replace `_export` stub with real implementation**

```dart
void _export(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(host: widget.host),
  );
}
```

- [ ] **Step 5: Verify `dart:convert` is already imported**

Check the top of `hosts_dashboard.dart` — `import 'dart:convert';` is already on line 1. `JsonEncoder` is available.

- [ ] **Step 6: Run the app and verify**

```bash
cd app && flutter run -d macos
```

Right-click a host → tap "Export" → dialog appears with `.ssh/config` tab selected → text is correct → switch to JSON tab → text updates → Copy button copies to clipboard → SnackBar appears.

- [ ] **Step 7: Run all tests**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 8: Run analyzer**

```bash
cd app && flutter analyze
```

Expected: no issues.

- [ ] **Step 9: Commit**

```bash
cd app && git add lib/widgets/hosts_dashboard.dart test/widgets/hosts_dashboard_menu_test.dart
git commit -m "feat: add Export action to host menu"
```
