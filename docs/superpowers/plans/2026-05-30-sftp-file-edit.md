# SFTP File Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add "Edit" to the SFTP right-click context menu, a "New file" toolbar button that creates and opens a file, and an unsaved-changes warning when closing the editor.

**Architecture:** All changes extend existing components — no new files. `SftpEntryContextMenu` gains an `onEdit` callback; `SftpFileOpsService` gets a `createFile` method; `CodeEditorScreen` tracks dirty state via a JS `change` event from Monaco and blocks back-navigation with `PopScope`; `SftpPanel` wires everything together.

**Tech Stack:** Flutter (Dart), Monaco Editor (webview_flutter), dartssh2 SFTP

---

## File Map

| File | Change |
|------|--------|
| `app/assets/monaco_editor.html` | Add `_contentLoaded` guard + `change` event emission |
| `app/lib/services/sftp_file_ops_service.dart` | Add `createFile` method |
| `app/lib/widgets/sftp_entry_context_menu.dart` | Add optional `onEdit` callback + "Edit" menu item |
| `app/lib/widgets/code_editor_screen.dart` | Add `_isDirty` tracking, `PopScope`, discard dialog |
| `app/lib/widgets/sftp_panel.dart` | Wire `onEdit`, add New File button + `_showNewFileDialog` |

---

## Task 1: Emit `change` event from Monaco (with load guard)

**Files:**
- Modify: `app/assets/monaco_editor.html`

Context: Monaco's `onDidChangeModelContent` also fires when `editor.setValue()` is called during `loadContent`. We need a `_contentLoaded` guard so only user edits trigger the `change` event sent to Flutter.

- [ ] **Step 1: Update `monaco_editor.html`**

Replace the entire `<script>` block (lines 26–71) with:

```html
  <script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.47.0/min/vs/loader.js"></script>
  <script>
    require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.47.0/min/vs' } });
    require(['vs/editor/editor.main'], function () {
      const editor = monaco.editor.create(document.getElementById('editor'), {
        value: '',
        language: 'plaintext',
        theme: 'vs-dark',
        fontSize: 13,
        fontFamily: 'monospace',
        automaticLayout: true,
        minimap: { enabled: false },
        scrollBeyondLastLine: false,
      });

      document.getElementById('editor').style.height = 'calc(100% - 24px)';

      let _contentLoaded = false;

      editor.onDidChangeCursorPosition(e => {
        document.getElementById('status-pos').textContent =
          `Ln ${e.position.lineNumber}, Col ${e.position.column}`;
      });

      editor.onDidChangeModelContent(function() {
        if (!_contentLoaded) return;
        if (window.FlutterChannel) {
          window.FlutterChannel.postMessage(JSON.stringify({ type: 'change' }));
        }
      });

      window.loadContent = function(content, language) {
        _contentLoaded = false;
        monaco.editor.setModelLanguage(editor.getModel(), language || 'plaintext');
        editor.setValue(content);
        document.getElementById('status-lang').textContent = language || 'Plain Text';
        editor.setScrollPosition({ scrollTop: 0 });
        _contentLoaded = true;
      };

      window.getContent = function() {
        return editor.getValue();
      };

      editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function() {
        if (window.FlutterChannel) {
          window.FlutterChannel.postMessage(JSON.stringify({
            type: 'save',
            content: editor.getValue(),
          }));
        }
      });

      if (window.FlutterChannel) {
        window.FlutterChannel.postMessage(JSON.stringify({ type: 'ready' }));
      }
    });
  </script>
```

- [ ] **Step 2: Verify analyze passes**

```bash
cd app && flutter analyze
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add app/assets/monaco_editor.html
git commit -m "feat: emit change event from Monaco editor with load guard"
```

---

## Task 2: Add `createFile` to `SftpFileOpsService`

**Files:**
- Modify: `app/lib/services/sftp_file_ops_service.dart`

- [ ] **Step 1: Add `createFile` method**

Open `app/lib/services/sftp_file_ops_service.dart`. Add this method after `mkdir` (before `delete`):

```dart
  Future<void> createFile(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await file.close();
    } finally {
      sftp.close();
    }
  }
```

The full file after change:

```dart
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import '../models/host.dart';
import 'ssh_service.dart';

class SftpFileOpsService {
  final SshService _sshService;

  SftpFileOpsService(this._sshService);

  Future<void> rename(Host host, String oldPath, String newPath) async {
    final sftp = await _sshService.openSftp(host);
    try {
      await sftp.rename(oldPath, newPath);
    } finally {
      sftp.close();
    }
  }

  Future<void> mkdir(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      await sftp.mkdir(path);
    } finally {
      sftp.close();
    }
  }

  Future<void> createFile(Host host, String path) async {
    final sftp = await _sshService.openSftp(host);
    try {
      final file = await sftp.open(
        path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      await file.close();
    } finally {
      sftp.close();
    }
  }

  Future<void> delete(Host host, String path, {required bool isDirectory}) async {
    final sftp = await _sshService.openSftp(host);
    try {
      if (isDirectory) {
        await _deleteRecursive(sftp, path);
      } else {
        await sftp.remove(path);
      }
    } finally {
      sftp.close();
    }
  }

  Future<void> _deleteRecursive(SftpClient sftp, String path) async {
    final items = await sftp.listdir(path);
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final child = p.posix.join(path, item.filename);
      if (item.attr.isDirectory) {
        await _deleteRecursive(sftp, child);
      } else {
        await sftp.remove(child);
      }
    }
    await sftp.rmdir(path);
  }
}
```

- [ ] **Step 2: Verify analyze passes**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/sftp_file_ops_service.dart
git commit -m "feat: add createFile to SftpFileOpsService"
```

---

## Task 3: Add "Edit" to `SftpEntryContextMenu`

**Files:**
- Modify: `app/lib/widgets/sftp_entry_context_menu.dart`

- [ ] **Step 1: Update the context menu widget**

Replace the entire file with:

```dart
// app/lib/widgets/sftp_entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/sftp_entry.dart';

class SftpEntryContextMenu extends StatelessWidget {
  final SftpEntry entry;
  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const SftpEntryContextMenu({
    super.key,
    required this.entry,
    required this.child,
    required this.onOpen,
    this.onEdit,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }

  void _show(BuildContext context, Offset pos) {
    final size = MediaQuery.of(context).size;
    showMenu<_Action>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, size.width - pos.dx, size.height - pos.dy),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2A2A2A)),
      ),
      items: [
        PopupMenuItem(
          value: _Action.open,
          height: 34,
          child: _Item(icon: entry.isDirectory ? Icons.folder_open : Icons.open_in_new,
              label: entry.isDirectory ? 'Enter' : 'Open'),
        ),
        if (!entry.isDirectory && onEdit != null)
          const PopupMenuItem(value: _Action.edit, height: 34,
              child: _Item(icon: Icons.edit_outlined, label: 'Edit')),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(value: _Action.rename, height: 34,
            child: _Item(icon: Icons.drive_file_rename_outline, label: 'Rename')),
        const PopupMenuItem(value: _Action.delete, height: 34,
            child: _Item(icon: Icons.delete_outline, label: 'Delete', color: Color(0xFFEF4444))),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(value: _Action.copyPath, height: 34,
            child: _Item(icon: Icons.content_copy, label: 'Copy path')),
      ],
    ).then((a) {
      if (a == null) return;
      switch (a) {
        case _Action.open: onOpen();
        case _Action.edit: onEdit?.call();
        case _Action.rename: onRename();
        case _Action.delete: onDelete();
        case _Action.copyPath: Clipboard.setData(ClipboardData(text: entry.path));
      }
    });
  }
}

enum _Action { open, edit, rename, delete, copyPath }

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Item({required this.icon, required this.label, this.color = const Color(0xFFD4D4D4)});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: color, fontSize: 13)),
    ]);
  }
}
```

- [ ] **Step 2: Verify analyze passes**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/sftp_entry_context_menu.dart
git commit -m "feat: add Edit option to SFTP entry context menu"
```

---

## Task 4: Add dirty tracking and unsaved-changes dialog to `CodeEditorScreen`

**Files:**
- Modify: `app/lib/widgets/code_editor_screen.dart`

- [ ] **Step 1: Update `CodeEditorScreen`**

Replace the entire file with:

```dart
// app/lib/widgets/code_editor_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../services/sftp_transfer_service.dart';

class CodeEditorScreen extends StatefulWidget {
  final Host host;
  final SftpEntry entry;

  const CodeEditorScreen({
    super.key,
    required this.host,
    required this.entry,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _saving = false;
  bool _isDirty = false;
  String? _content;

  static const _langMap = {
    'dart': 'dart', 'py': 'python', 'js': 'javascript', 'ts': 'typescript',
    'json': 'json', 'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown',
    'sh': 'shell', 'bash': 'shell', 'zsh': 'shell', 'go': 'go',
    'rs': 'rust', 'c': 'c', 'cpp': 'cpp', 'html': 'html', 'css': 'css',
    'xml': 'xml', 'sql': 'sql', 'toml': 'ini',
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..loadFlutterAsset('assets/monaco_editor.html');
    _loadFile();
  }

  Future<void> _loadFile() async {
    final service = context.read<SftpTransferService>();
    final tmpPath = await service.downloadToTemp(widget.host, widget.entry);
    if (tmpPath == null || !mounted) return;
    final bytes = await File(tmpPath).readAsBytes();
    setState(() => _content = utf8.decode(bytes, allowMalformed: true));
    if (_ready) _pushContentToEditor();
  }

  void _onJsMessage(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    final type = data['type'] as String;
    if (type == 'ready') {
      setState(() => _ready = true);
      if (_content != null) _pushContentToEditor();
    } else if (type == 'change') {
      if (!_isDirty) setState(() => _isDirty = true);
    } else if (type == 'save') {
      final content = data['content'] as String;
      _saveFile(content);
    }
  }

  void _pushContentToEditor() {
    final lang = _langMap[widget.entry.extension] ?? 'plaintext';
    final escaped = jsonEncode(_content);
    _controller.runJavaScript('loadContent($escaped, "$lang")');
  }

  Future<void> _saveFile(String content) async {
    setState(() => _saving = true);
    try {
      final service = context.read<SftpTransferService>();
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = '${tmpDir.path}/${widget.entry.name}';
      await File(tmpPath).writeAsString(content);
      await service.uploadFile(widget.host, tmpPath, widget.entry.path);
      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDiscardDialog() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Unsaved changes',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: const Text('Discard changes and close?',
            style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showDiscardDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141414),
          title: Text(
            widget.entry.name,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22C55E)),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.save_outlined, size: 18),
              tooltip: 'Save (Ctrl+S)',
              onPressed: _saving
                  ? null
                  : () async {
                      final content =
                          await _controller.runJavaScriptReturningResult('getContent()');
                      await _saveFile(content.toString());
                    },
            ),
          ],
        ),
        body: !_ready
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
            : WebViewWidget(controller: _controller),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze passes**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/code_editor_screen.dart
git commit -m "feat: add dirty tracking and unsaved changes dialog to CodeEditorScreen"
```

---

## Task 5: Wire "Edit" and "New file" in `SftpPanel`

**Files:**
- Modify: `app/lib/widgets/sftp_panel.dart`

- [ ] **Step 1: Add `onEdit` to `_buildEntryTile` and "New file" button to `_buildPathBar`**

There are two targeted edits to make.

**Edit A** — in `_buildEntryTile`, update the `SftpEntryContextMenu` call to pass `onEdit`:

Find (around line 261–265):
```dart
    return SftpEntryContextMenu(
      entry: entry,
      onOpen: () => _onEntryTap(entry),
      onRename: () => _showRenameDialog(prov, entry),
      onDelete: () => _showDeleteConfirm(prov, [entry]),
```

Replace with:
```dart
    return SftpEntryContextMenu(
      entry: entry,
      onOpen: () => _onEntryTap(entry),
      onEdit: entry.isDirectory ? null : () => _onEntryTap(entry),
      onRename: () => _showRenameDialog(prov, entry),
      onDelete: () => _showDeleteConfirm(prov, [entry]),
```

**Edit B** — in `_buildPathBar`, add the "New file" button before the "New folder" button.

Find (around line 191):
```dart
          _ToolbarBtn(icon: Icons.create_new_folder_outlined, tooltip: 'New folder',
              enabled: true, onTap: () => _showNewFolderDialog(prov)),
```

Replace with:
```dart
          _ToolbarBtn(icon: Icons.note_add_outlined, tooltip: 'New file',
              enabled: true, onTap: () => _showNewFileDialog(prov)),
          _ToolbarBtn(icon: Icons.create_new_folder_outlined, tooltip: 'New folder',
              enabled: true, onTap: () => _showNewFolderDialog(prov)),
```

- [ ] **Step 2: Add `_showNewFileDialog` method**

Add this method after `_showNewFolderDialog` (before `_showRenameDialog`):

```dart
  Future<void> _showNewFileDialog(SftpPanelProvider prov) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New File',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'File name', hintStyle: TextStyle(color: Color(0xFF555555)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A2A))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF22C55E))),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create', style: TextStyle(color: Color(0xFF22C55E)))),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final remotePath =
          prov.currentPath == '/' ? '/$name' : '${prov.currentPath}/$name';
      await context.read<SftpFileOpsService>().createFile(widget.host!, remotePath);
      final entry = SftpEntry(
        name: name,
        path: remotePath,
        isDirectory: false,
        size: 0,
        modifiedAt: DateTime.now(),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CodeEditorScreen(host: widget.host!, entry: entry)),
      );
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Create file failed: $e'),
                backgroundColor: const Color(0xFF2A1A1A)));
      }
    }
  }
```

- [ ] **Step 3: Verify analyze passes and all tests pass**

```bash
cd app && flutter analyze && flutter test
```

Expected: no errors, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart
git commit -m "feat: add New File button and wire Edit in SFTP panel"
```

---

## Manual Testing Checklist

After all tasks complete, verify in the running app (`flutter run -d macos`):

- [ ] Right-click a **file** in SFTP panel → context menu shows "Open", "Edit", then divider, "Rename", "Delete"
- [ ] Right-click a **directory** → context menu shows "Enter" only (no "Edit")
- [ ] Click "Edit" → opens Monaco editor with file content
- [ ] Edit content in Monaco → back button shows "Discard changes?" dialog
- [ ] Click "Cancel" in dialog → stays in editor
- [ ] Click "Discard" → closes editor
- [ ] Click Save / Ctrl+S → saves successfully → back button closes without dialog
- [ ] Click "New file" button (note icon in toolbar) → dialog appears
- [ ] Enter filename + Create → file created on server → Monaco editor opens (empty)
- [ ] Save new file content → directory refreshes with new file on return
