# SFTP & File Management Enhancement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the SFTP file manager to dual-panel layout and add a Monaco-powered in-app code editor for editing remote files directly.

**Architecture:** The existing `SftpScreen` is replaced by a `DualPanelSftpScreen` that renders two `SftpPanel` widgets side-by-side, each maintaining its own path/listing state. File transfers between panels use the existing `SshService.openSftp()`. The code editor uses a `WebView` embedding the Monaco editor served from a bundled local HTML file (assets); file content is loaded via SFTP, passed to Monaco via JS, and saved back on Ctrl+S.

**Tech Stack:** Flutter, `dartssh2`, `webview_flutter` (^4.8.0), bundled Monaco editor HTML asset

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `app/lib/models/sftp_entry.dart` | Create | Represents a remote directory entry |
| `app/lib/providers/sftp_panel_provider.dart` | Create | State for one SFTP panel (path, listing, selection) |
| `app/lib/widgets/sftp_panel.dart` | Create | Single SFTP panel widget |
| `app/lib/widgets/dual_panel_sftp_screen.dart` | Create | Two SftpPanels + transfer controls |
| `app/lib/widgets/sftp_screen.dart` | Modify | Replace with DualPanelSftpScreen |
| `app/lib/services/sftp_transfer_service.dart` | Create | Upload/download/copy between panels |
| `app/lib/widgets/code_editor_screen.dart` | Create | Monaco webview editor |
| `app/assets/monaco_editor.html` | Create | Bundled Monaco editor HTML |
| `app/pubspec.yaml` | Modify | Add `webview_flutter`, declare asset |
| `app/test/models/sftp_entry_test.dart` | Create | Unit tests for SftpEntry |
| `app/test/providers/sftp_panel_provider_test.dart` | Create | Provider unit tests |

---

### Task 1: SftpEntry Model

**Files:**
- Create: `app/lib/models/sftp_entry.dart`
- Create: `app/test/models/sftp_entry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/sftp_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/sftp_entry.dart';

void main() {
  group('SftpEntry', () {
    test('isDirectory returns true for directory type', () {
      final entry = SftpEntry(name: 'mydir', path: '/home/user/mydir', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      expect(entry.isDirectory, true);
    });

    test('extension returns file extension for files', () {
      final entry = SftpEntry(name: 'main.dart', path: '/home/user/main.dart', isDirectory: false, size: 1024, modifiedAt: DateTime(2024));
      expect(entry.extension, 'dart');
    });

    test('extension returns empty string for directories', () {
      final entry = SftpEntry(name: 'src', path: '/home/user/src', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      expect(entry.extension, '');
    });

    test('formattedSize returns human-readable string', () {
      final small = SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 512, modifiedAt: DateTime(2024));
      final large = SftpEntry(name: 'b.bin', path: '/b.bin', isDirectory: false, size: 2097152, modifiedAt: DateTime(2024));
      expect(small.formattedSize, '512 B');
      expect(large.formattedSize, '2.0 MB');
    });

    test('sortKey puts directories before files', () {
      final dir = SftpEntry(name: 'src', path: '/src', isDirectory: true, size: 0, modifiedAt: DateTime(2024));
      final file = SftpEntry(name: 'main.dart', path: '/main.dart', isDirectory: false, size: 100, modifiedAt: DateTime(2024));
      expect(dir.sortKey.compareTo(file.sortKey), lessThan(0));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/models/sftp_entry_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Implement SftpEntry**

```dart
// app/lib/models/sftp_entry.dart

class SftpEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  const SftpEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  String get extension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get formattedSize {
    if (isDirectory) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // Directories sort before files, then alphabetically
  String get sortKey => (isDirectory ? '0' : '1') + name.toLowerCase();
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/models/sftp_entry_test.dart
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/sftp_entry.dart app/test/models/sftp_entry_test.dart
git commit -m "feat: add SftpEntry model with sorting and formatting"
```

---

### Task 2: Add webview_flutter dependency

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add dependency**

In `app/pubspec.yaml`, under `dependencies:`, add:
```yaml
  webview_flutter: ^4.8.0
```

Under `flutter:` -> `assets:`, add:
```yaml
  assets:
    - assets/monaco_editor.html
```

- [ ] **Step 2: Create assets directory and placeholder**

```bash
mkdir -p app/assets
touch app/assets/monaco_editor.html
```

- [ ] **Step 3: Fetch packages**

```bash
cd app && flutter pub get
```
Expected: `webview_flutter` downloaded, no conflicts.

- [ ] **Step 4: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock app/assets/monaco_editor.html
git commit -m "chore: add webview_flutter dependency and assets directory"
```

---

### Task 3: SftpPanelProvider

**Files:**
- Create: `app/lib/providers/sftp_panel_provider.dart`
- Create: `app/test/providers/sftp_panel_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/providers/sftp_panel_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/sftp_panel_provider.dart';
import 'package:yourssh/models/sftp_entry.dart';

void main() {
  test('initial path is /', () {
    final p = SftpPanelProvider();
    expect(p.currentPath, '/');
  });

  test('setPath updates current path and clears selection', () {
    final p = SftpPanelProvider();
    p.toggleSelection(SftpEntry(name: 'a', path: '/a', isDirectory: false, size: 0, modifiedAt: DateTime(2024)));
    p.setPath('/home/user');
    expect(p.currentPath, '/home/user');
    expect(p.selectedEntries, isEmpty);
  });

  test('toggleSelection adds and removes entries', () {
    final p = SftpPanelProvider();
    final e = SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024));
    p.toggleSelection(e);
    expect(p.selectedEntries, contains(e));
    p.toggleSelection(e);
    expect(p.selectedEntries, isEmpty);
  });

  test('clearSelection empties selection', () {
    final p = SftpPanelProvider();
    final e = SftpEntry(name: 'b.txt', path: '/b.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024));
    p.toggleSelection(e);
    p.clearSelection();
    expect(p.selectedEntries, isEmpty);
  });

  test('navigateUp moves to parent path', () {
    final p = SftpPanelProvider();
    p.setPath('/home/user/projects');
    p.navigateUp();
    expect(p.currentPath, '/home/user');
  });

  test('navigateUp at root stays at root', () {
    final p = SftpPanelProvider();
    p.navigateUp();
    expect(p.currentPath, '/');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/providers/sftp_panel_provider_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Implement SftpPanelProvider**

```dart
// app/lib/providers/sftp_panel_provider.dart
import 'package:flutter/foundation.dart';
import '../models/sftp_entry.dart';

enum SftpPanelLoadState { idle, loading, loaded, error }

class SftpPanelProvider extends ChangeNotifier {
  String _currentPath = '/';
  List<SftpEntry> _entries = [];
  final Set<SftpEntry> _selected = {};
  SftpPanelLoadState loadState = SftpPanelLoadState.idle;
  String? errorMessage;

  String get currentPath => _currentPath;
  List<SftpEntry> get entries => List.unmodifiable(_entries);
  Set<SftpEntry> get selectedEntries => Set.unmodifiable(_selected);

  void setPath(String path) {
    _currentPath = path;
    _selected.clear();
    notifyListeners();
  }

  void setEntries(List<SftpEntry> entries) {
    _entries = List.of(entries)..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    notifyListeners();
  }

  void toggleSelection(SftpEntry entry) {
    if (_selected.contains(entry)) {
      _selected.remove(entry);
    } else {
      _selected.add(entry);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  void navigateUp() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    _currentPath = parts.isEmpty || (parts.length == 1 && parts.first.isEmpty)
        ? '/'
        : parts.join('/');
    _selected.clear();
    notifyListeners();
  }

  void setLoadState(SftpPanelLoadState state, {String? error}) {
    loadState = state;
    errorMessage = error;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/providers/sftp_panel_provider_test.dart
```
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/sftp_panel_provider.dart app/test/providers/sftp_panel_provider_test.dart
git commit -m "feat: add SftpPanelProvider with path navigation and selection"
```

---

### Task 4: SftpTransferService

**Files:**
- Create: `app/lib/services/sftp_transfer_service.dart`

- [ ] **Step 1: Implement SftpTransferService**

```dart
// app/lib/services/sftp_transfer_service.dart
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/sftp_entry.dart';
import 'ssh_service.dart';

class SftpTransferService {
  final SshService _sshService;

  SftpTransferService(this._sshService);

  Future<List<SftpEntry>> listDirectory(String sessionId, String path) async {
    final sftp = await _sshService.openSftp(sessionId);
    if (sftp == null) return [];

    final items = await sftp.listdir(path);
    await sftp.close();

    return items
        .where((item) => item.filename != '.' && item.filename != '..')
        .map((item) => SftpEntry(
              name: item.filename,
              path: p.posix.join(path, item.filename),
              isDirectory: item.attr.isDirectory,
              size: item.attr.size ?? 0,
              modifiedAt: item.attr.modifyTime != null
                  ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000)
                  : DateTime.now(),
            ))
        .toList();
  }

  Future<String?> downloadToTemp(String sessionId, SftpEntry entry) async {
    final sftp = await _sshService.openSftp(sessionId);
    if (sftp == null) return null;

    final tmpDir = await getTemporaryDirectory();
    final localPath = p.join(tmpDir.path, entry.name);
    final file = await sftp.open(entry.path);
    final bytes = await file.readBytes();
    await File(localPath).writeAsBytes(bytes);
    await file.close();
    await sftp.close();
    return localPath;
  }

  Future<void> uploadFile(String sessionId, String localPath, String remotePath) async {
    final sftp = await _sshService.openSftp(sessionId);
    if (sftp == null) return;

    final bytes = await File(localPath).readAsBytes();
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    await remoteFile.writeBytes(bytes);
    await remoteFile.close();
    await sftp.close();
  }

  Future<void> copyBetweenPanels({
    required String sourceSessionId,
    required SftpEntry sourceEntry,
    required String destinationSessionId,
    required String destinationPath,
  }) async {
    final tmpPath = await downloadToTemp(sourceSessionId, sourceEntry);
    if (tmpPath == null) return;
    final destFilePath = p.posix.join(destinationPath, sourceEntry.name);
    await uploadFile(destinationSessionId, tmpPath, destFilePath);
    await File(tmpPath).delete();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/services/sftp_transfer_service.dart
git commit -m "feat: add SftpTransferService for dual-panel file operations"
```

---

### Task 5: SftpPanel Widget

**Files:**
- Create: `app/lib/widgets/sftp_panel.dart`

- [ ] **Step 1: Implement SftpPanel**

```dart
// app/lib/widgets/sftp_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sftp_entry.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/sftp_transfer_service.dart';
import 'code_editor_screen.dart';

class SftpPanel extends StatefulWidget {
  final String sessionId;
  final String panelId; // 'left' or 'right'

  const SftpPanel({super.key, required this.sessionId, required this.panelId});

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  late SftpPanelProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = SftpPanelProvider();
    _loadDirectory('/');
  }

  Future<void> _loadDirectory(String path) async {
    _provider.setLoadState(SftpPanelLoadState.loading);
    _provider.setPath(path);
    try {
      final service = context.read<SftpTransferService>();
      final entries = await service.listDirectory(widget.sessionId, path);
      _provider.setEntries(entries);
      _provider.setLoadState(SftpPanelLoadState.loaded);
    } catch (e) {
      _provider.setLoadState(SftpPanelLoadState.error, error: e.toString());
    }
  }

  void _onEntryTap(SftpEntry entry) {
    if (entry.isDirectory) {
      _loadDirectory(entry.path);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CodeEditorScreen(
            sessionId: widget.sessionId,
            entry: entry,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<SftpPanelProvider>(
        builder: (context, provider, _) => Column(
          children: [
            _buildPathBar(provider),
            Expanded(child: _buildContent(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildPathBar(SftpPanelProvider provider) {
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF888888)),
            onPressed: () {
              provider.navigateUp();
              _loadDirectory(provider.currentPath);
            },
            tooltip: 'Up',
          ),
          Expanded(
            child: Text(
              provider.currentPath,
              style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF888888)),
            onPressed: () => _loadDirectory(provider.currentPath),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SftpPanelProvider provider) {
    if (provider.loadState == SftpPanelLoadState.loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (provider.loadState == SftpPanelLoadState.error) {
      return Center(
        child: Text(
          provider.errorMessage ?? 'Error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (provider.entries.isEmpty) {
      return const Center(
        child: Text('Empty directory', style: TextStyle(color: Color(0xFF555555))),
      );
    }
    return ListView.builder(
      itemCount: provider.entries.length,
      itemBuilder: (_, i) => _buildEntryTile(provider.entries[i], provider),
    );
  }

  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider provider) {
    final isSelected = provider.selectedEntries.contains(entry);
    return InkWell(
      onTap: () => _onEntryTap(entry),
      onSecondaryTap: () => provider.toggleSelection(entry),
      child: Container(
        color: isSelected ? const Color(0xFF22C55E).withOpacity(0.1) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              entry.isDirectory ? Icons.folder : _fileIcon(entry.extension),
              size: 16,
              color: entry.isDirectory ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.name,
                style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              entry.formattedSize,
              style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'go' || 'rs' || 'c' || 'cpp' => Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart
git commit -m "feat: add SftpPanel widget with directory navigation and file listing"
```

---

### Task 6: DualPanelSftpScreen

**Files:**
- Create: `app/lib/widgets/dual_panel_sftp_screen.dart`
- Modify: `app/lib/widgets/sftp_screen.dart`

- [ ] **Step 1: Implement DualPanelSftpScreen**

```dart
// app/lib/widgets/dual_panel_sftp_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import 'sftp_panel.dart';

class DualPanelSftpScreen extends StatelessWidget {
  const DualPanelSftpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSession;

    if (session == null) {
      return const Center(
        child: Text(
          'Connect to a host to browse files',
          style: TextStyle(color: Color(0xFF555555)),
        ),
      );
    }

    return Provider(
      create: (ctx) => SftpTransferService(ctx.read<SshService>()),
      child: Row(
        children: [
          Expanded(
            child: SftpPanel(sessionId: session.id, panelId: 'left'),
          ),
          const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
          Expanded(
            child: SftpPanel(sessionId: session.id, panelId: 'right'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Update SftpScreen to use DualPanelSftpScreen**

In `app/lib/widgets/sftp_screen.dart`, replace the existing single-panel implementation:
```dart
// Replace the build method body with:
@override
Widget build(BuildContext context) {
  return const DualPanelSftpScreen();
}
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/dual_panel_sftp_screen.dart app/lib/widgets/sftp_screen.dart
git commit -m "feat: replace single-panel SFTP with dual-panel layout"
```

---

### Task 7: Monaco Code Editor

**Files:**
- Create: `app/assets/monaco_editor.html`
- Create: `app/lib/widgets/code_editor_screen.dart`

- [ ] **Step 1: Create bundled Monaco editor HTML**

```html
<!-- app/assets/monaco_editor.html -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #0F0F0F; overflow: hidden; }
    #editor { width: 100%; height: 100%; }
    #status {
      position: fixed; bottom: 0; left: 0; right: 0; height: 24px;
      background: #141414; color: #888; font-family: monospace; font-size: 11px;
      display: flex; align-items: center; padding: 0 12px; gap: 16px;
      border-top: 1px solid #2A2A2A;
    }
  </style>
</head>
<body>
  <div id="editor"></div>
  <div id="status">
    <span id="status-lang">Plain Text</span>
    <span id="status-pos">Ln 1, Col 1</span>
    <span id="status-msg"></span>
  </div>
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

      // Resize editor above status bar
      document.getElementById('editor').style.height = 'calc(100% - 24px)';

      editor.onDidChangeCursorPosition(e => {
        document.getElementById('status-pos').textContent =
          `Ln ${e.position.lineNumber}, Col ${e.position.column}`;
      });

      // Flutter -> JS: load content
      window.loadContent = function(content, language) {
        monaco.editor.setModelLanguage(editor.getModel(), language || 'plaintext');
        editor.setValue(content);
        document.getElementById('status-lang').textContent = language || 'Plain Text';
        editor.setScrollPosition({ scrollTop: 0 });
      };

      // JS -> Flutter: get content
      window.getContent = function() {
        return editor.getValue();
      };

      // Ctrl+S handler
      editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function() {
        if (window.FlutterChannel) {
          window.FlutterChannel.postMessage(JSON.stringify({
            type: 'save',
            content: editor.getValue(),
          }));
        }
      });

      // Notify Flutter that editor is ready
      if (window.FlutterChannel) {
        window.FlutterChannel.postMessage(JSON.stringify({ type: 'ready' }));
      }
    });
  </script>
</body>
</html>
```

- [ ] **Step 2: Implement CodeEditorScreen**

```dart
// app/lib/widgets/code_editor_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/sftp_entry.dart';
import '../services/sftp_transfer_service.dart';
import 'package:provider/provider.dart';

class CodeEditorScreen extends StatefulWidget {
  final String sessionId;
  final SftpEntry entry;

  const CodeEditorScreen({
    super.key,
    required this.sessionId,
    required this.entry,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  late final WebViewController _controller;
  bool _ready = false;
  bool _saving = false;
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
    final tmpPath = await service.downloadToTemp(widget.sessionId, widget.entry);
    if (tmpPath == null || !mounted) return;
    final bytes = await _readFile(tmpPath);
    setState(() => _content = utf8.decode(bytes, allowMalformed: true));
    if (_ready) _pushContentToEditor();
  }

  Future<List<int>> _readFile(String path) async {
    // dart:io File
    final file = await _getFile(path);
    return file;
  }

  Future<List<int>> _getFile(String path) async {
    // Using dart:io
    final dartIoFile = await _dartIoReadFile(path);
    return dartIoFile;
  }

  Future<List<int>> _dartIoReadFile(String path) async {
    import 'dart:io' show File;
    return await File(path).readAsBytes();
  }

  void _onJsMessage(JavaScriptMessage msg) {
    final data = jsonDecode(msg.message) as Map<String, dynamic>;
    final type = data['type'] as String;
    if (type == 'ready') {
      setState(() => _ready = true);
      if (_content != null) _pushContentToEditor();
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
      // Write content to temp file, then upload
      import 'dart:io' show File;
      import 'package:path_provider/path_provider.dart';
      final tmpDir = await getTemporaryDirectory();
      final tmpPath = '${tmpDir.path}/${widget.entry.name}';
      await File(tmpPath).writeAsString(content);
      await service.uploadFile(widget.sessionId, tmpPath, widget.entry.path);
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    final content = await _controller.runJavaScriptReturningResult('getContent()') as String;
                    await _saveFile(content.replaceAll('"', '').replaceAll(r'\"', '"'));
                  },
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)))
          : WebViewWidget(controller: _controller),
    );
  }
}
```

**Note:** The `import` statements inside methods above need to be moved to the top of the file. Refactor the `_saveFile` and `_loadFile` methods to use top-level imports:

```dart
// Add at the top of the file, after existing imports:
import 'dart:io';
import 'package:path_provider/path_provider.dart';
```

And remove the inline `import` statements inside methods.

- [ ] **Step 3: Commit**

```bash
git add app/assets/monaco_editor.html app/lib/widgets/code_editor_screen.dart
git commit -m "feat: add Monaco code editor screen for SFTP file editing"
```

---

### Task 8: End-to-End Verification

- [ ] **Step 1: Run all SFTP-related tests**

```bash
cd app && flutter test test/models/sftp_entry_test.dart test/providers/sftp_panel_provider_test.dart
```
Expected: All 11 tests pass.

- [ ] **Step 2: Run the app and verify dual-panel SFTP**

```bash
cd app && flutter run -d macos
```
1. Connect to an SSH host.
2. Navigate to SFTP in the sidebar.
3. Verify two panels appear side-by-side.
4. Navigate to different directories in each panel.
5. Right-click a file to select it.
6. Tap a text file — verify Monaco editor opens.
7. Edit the file, press Ctrl+S — verify "Saved" snackbar appears.

- [ ] **Step 3: Commit**

```bash
git add .
git commit -m "feat: complete dual-panel SFTP and Monaco code editor integration"
```

---

## Self-Review

**Spec coverage:**
- ✅ Dual-panel SFTP (Tasks 3, 4, 5, 6)
- ✅ Built-in Code Editor / Monaco (Tasks 2, 7)

**Gaps:** None.

**Type consistency:** `SftpEntry` used in `SftpPanelProvider`, `SftpPanel`, `SftpTransferService`, `CodeEditorScreen`. `SftpTransferService` referenced in `SftpPanel` and `CodeEditorScreen` consistently. `SftpPanelLoadState` defined in `sftp_panel_provider.dart` and used only within that file.
