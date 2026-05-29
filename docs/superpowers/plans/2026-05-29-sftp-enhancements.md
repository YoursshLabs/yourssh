# SFTP Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rename/delete/mkdir, checkbox multi-select, folder transfer with skip-existing, per-file progress dialog, and a second remote panel (3-column layout) to the SFTP screen.

**Architecture:** New `SftpTransferItem` model and `SftpTransferProvider` manage transfer queue + progress state. A new `SftpFileOpsService` handles rename/delete/mkdir. `SftpTransferService` gains folder-recursive methods with progress callbacks. `SftpPanel` is updated with checkbox column, toolbar, and right-click context menu. `DualPanelSftpScreen` becomes 3-column (Local | RemoteA | RemoteB) and owns the shared `SftpTransferProvider`.

**Tech Stack:** Flutter, Dart, dartssh2 (SFTP), provider package, uuid package

---

### Task 1: SftpTransferItem model

**Files:**
- Create: `app/lib/models/sftp_transfer_item.dart`
- Create: `app/test/models/sftp_transfer_item_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/sftp_transfer_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/sftp_transfer_item.dart';

void main() {
  group('SftpTransferItem', () {
    test('progress is 0 when totalBytes is 0', () {
      final item = SftpTransferItem(
        id: '1',
        fileName: 'file.txt',
        direction: TransferDirection.upload,
      );
      expect(item.progress, 0.0);
    });

    test('progress calculates correctly', () {
      final item = SftpTransferItem(
        id: '2',
        fileName: 'file.txt',
        direction: TransferDirection.download,
      )
        ..totalBytes = 1000
        ..bytesTransferred = 500;
      expect(item.progress, 0.5);
    });

    test('initial status is pending', () {
      final item = SftpTransferItem(
        id: '3',
        fileName: 'file.txt',
        direction: TransferDirection.upload,
      );
      expect(item.status, TransferStatus.pending);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd app && flutter test test/models/sftp_transfer_item_test.dart
```
Expected: FAIL — file not found.

- [ ] **Step 3: Create the model**

```dart
// app/lib/models/sftp_transfer_item.dart
import 'package:uuid/uuid.dart';

enum TransferDirection { upload, download }
enum TransferStatus { pending, inProgress, done, skipped, error }

class SftpTransferItem {
  final String id;
  final String fileName;
  final TransferDirection direction;
  TransferStatus status;
  int bytesTransferred;
  int totalBytes;
  String? errorMessage;

  SftpTransferItem({
    String? id,
    required this.fileName,
    required this.direction,
    this.status = TransferStatus.pending,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();

  double get progress => totalBytes > 0 ? bytesTransferred / totalBytes : 0;
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd app && flutter test test/models/sftp_transfer_item_test.dart
```
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/sftp_transfer_item.dart app/test/models/sftp_transfer_item_test.dart
git commit -m "feat: add SftpTransferItem model"
```

---

### Task 2: SftpTransferProvider

**Files:**
- Create: `app/lib/providers/sftp_transfer_provider.dart`
- Create: `app/test/providers/sftp_transfer_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/providers/sftp_transfer_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/sftp_transfer_provider.dart';
import 'package:yourssh/models/sftp_transfer_item.dart';

void main() {
  group('SftpTransferProvider', () {
    test('isTransferring is false when empty', () {
      expect(SftpTransferProvider().isTransferring, false);
    });

    test('isTransferring is true when an item is inProgress', () {
      final p = SftpTransferProvider();
      final item = SftpTransferItem(fileName: 'a.txt', direction: TransferDirection.upload)
        ..status = TransferStatus.inProgress;
      p.startBatch([item]);
      expect(p.isTransferring, true);
    });

    test('overallProgress is 0 with no items', () {
      expect(SftpTransferProvider().overallProgress, 0.0);
    });

    test('overallProgress calculates from total bytes', () {
      final p = SftpTransferProvider();
      final item = SftpTransferItem(fileName: 'a.txt', direction: TransferDirection.upload)
        ..totalBytes = 1000
        ..bytesTransferred = 250;
      p.startBatch([item]);
      expect(p.overallProgress, 0.25);
    });

    test('updateItem modifies the matching item', () {
      final p = SftpTransferProvider();
      final item = SftpTransferItem(id: 'abc', fileName: 'a.txt', direction: TransferDirection.upload)
        ..totalBytes = 1000;
      p.startBatch([item]);
      p.updateItem('abc', bytesTransferred: 500, status: TransferStatus.inProgress);
      expect(p.items.first.bytesTransferred, 500);
      expect(p.items.first.status, TransferStatus.inProgress);
    });

    test('cancel sets isCancelled to true', () {
      final p = SftpTransferProvider();
      p.cancel();
      expect(p.isCancelled, true);
    });

    test('clear removes all items and resets cancelled', () {
      final p = SftpTransferProvider();
      p.startBatch([SftpTransferItem(fileName: 'a.txt', direction: TransferDirection.upload)]);
      p.cancel();
      p.clear();
      expect(p.items, isEmpty);
      expect(p.isCancelled, false);
    });

    test('completedCount counts done and skipped items', () {
      final p = SftpTransferProvider();
      p.startBatch([
        SftpTransferItem(id: '1', fileName: 'a.txt', direction: TransferDirection.upload)..status = TransferStatus.done,
        SftpTransferItem(id: '2', fileName: 'b.txt', direction: TransferDirection.upload)..status = TransferStatus.skipped,
        SftpTransferItem(id: '3', fileName: 'c.txt', direction: TransferDirection.upload),
      ]);
      expect(p.completedCount, 2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd app && flutter test test/providers/sftp_transfer_provider_test.dart
```
Expected: FAIL — file not found.

- [ ] **Step 3: Create the provider**

```dart
// app/lib/providers/sftp_transfer_provider.dart
import 'package:flutter/foundation.dart';
import '../models/sftp_transfer_item.dart';

class SftpTransferProvider extends ChangeNotifier {
  List<SftpTransferItem> _items = [];
  bool _cancelled = false;

  List<SftpTransferItem> get items => List.unmodifiable(_items);
  bool get isCancelled => _cancelled;

  bool get isTransferring =>
      _items.any((i) => i.status == TransferStatus.inProgress);

  double get overallProgress {
    final total = _items.fold<int>(0, (s, i) => s + i.totalBytes);
    if (total == 0) return 0;
    return _items.fold<int>(0, (s, i) => s + i.bytesTransferred) / total;
  }

  int get completedCount => _items
      .where((i) => i.status == TransferStatus.done || i.status == TransferStatus.skipped)
      .length;

  int get totalCount => _items.length;

  void startBatch(List<SftpTransferItem> items) {
    _items = List.of(items);
    _cancelled = false;
    notifyListeners();
  }

  void updateItem(String id, {int? bytesTransferred, TransferStatus? status, String? errorMessage}) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    final item = _items[idx];
    if (bytesTransferred != null) item.bytesTransferred = bytesTransferred;
    if (status != null) item.status = status;
    if (errorMessage != null) item.errorMessage = errorMessage;
    notifyListeners();
  }

  void cancel() {
    _cancelled = true;
    notifyListeners();
  }

  void clear() {
    _items = [];
    _cancelled = false;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/providers/sftp_transfer_provider_test.dart
```
Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/sftp_transfer_provider.dart app/test/providers/sftp_transfer_provider_test.dart
git commit -m "feat: add SftpTransferProvider"
```

---

### Task 3: SftpPanelProvider — selectAll / deselectAll

**Files:**
- Modify: `app/lib/providers/sftp_panel_provider.dart`
- Modify: `app/test/providers/sftp_panel_provider_test.dart`

- [ ] **Step 1: Append failing tests to existing test file**

Add inside `main()` in `app/test/providers/sftp_panel_provider_test.dart`:

```dart
  test('selectAll selects all entries', () {
    final p = SftpPanelProvider();
    p.setEntries([
      SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024)),
      SftpEntry(name: 'b.txt', path: '/b.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024)),
    ]);
    p.selectAll();
    expect(p.selectedEntries.length, 2);
  });

  test('deselectAll clears selection', () {
    final p = SftpPanelProvider();
    final e = SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024));
    p.setEntries([e]);
    p.selectAll();
    p.deselectAll();
    expect(p.selectedEntries, isEmpty);
  });

  test('isAllSelected is true when all entries are selected', () {
    final p = SftpPanelProvider();
    p.setEntries([SftpEntry(name: 'a.txt', path: '/a.txt', isDirectory: false, size: 0, modifiedAt: DateTime(2024))]);
    expect(p.isAllSelected, false);
    p.selectAll();
    expect(p.isAllSelected, true);
  });
```

- [ ] **Step 2: Run to confirm new tests fail**

```bash
cd app && flutter test test/providers/sftp_panel_provider_test.dart
```
Expected: 5 pass, 3 new FAIL.

- [ ] **Step 3: Add methods to SftpPanelProvider**

Add after `clearSelection()` in `app/lib/providers/sftp_panel_provider.dart`:

```dart
  void selectAll() {
    for (final entry in _entries) {
      _selected.add(entry);
    }
    notifyListeners();
  }

  void deselectAll() {
    _selected.clear();
    notifyListeners();
  }

  bool get isAllSelected => _entries.isNotEmpty && _selected.length == _entries.length;
```

- [ ] **Step 4: Run all provider tests**

```bash
cd app && flutter test test/providers/sftp_panel_provider_test.dart
```
Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/sftp_panel_provider.dart app/test/providers/sftp_panel_provider_test.dart
git commit -m "feat: add selectAll/deselectAll/isAllSelected to SftpPanelProvider"
```

---

### Task 4: SftpFileOpsService

**Files:**
- Create: `app/lib/services/sftp_file_ops_service.dart`

No unit tests — requires live SSH. Verified manually after Task 8.

- [ ] **Step 1: Create the service**

```dart
// app/lib/services/sftp_file_ops_service.dart
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

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze lib/services/sftp_file_ops_service.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/sftp_file_ops_service.dart
git commit -m "feat: add SftpFileOpsService (rename, delete, mkdir)"
```

---

### Task 5: SftpTransferService — folder transfer with progress

**Files:**
- Modify: `app/lib/services/sftp_transfer_service.dart`

- [ ] **Step 1: Add `dart:io` and `dart:typed_data` imports if missing**

Verify the top of `app/lib/services/sftp_transfer_service.dart` has:
```dart
import 'dart:io';
import 'dart:typed_data';
```
Both are already present in the original file. No change needed.

- [ ] **Step 2: Add private helpers and public folder methods**

Append to the `SftpTransferService` class body (before the closing `}`):

```dart
  Future<void> uploadDirectory({
    required String localDir,
    required Host remoteHost,
    required String remoteDir,
    required void Function(String filePath, int bytes, int total) onProgress,
    required void Function(String filePath) onFileSkipped,
    required bool Function() isCancelled,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    try {
      await _uploadDirRecursive(
        sftp: sftp,
        localDir: localDir,
        remoteDir: remoteDir,
        onProgress: onProgress,
        onFileSkipped: onFileSkipped,
        isCancelled: isCancelled,
      );
    } finally {
      sftp.close();
    }
  }

  Future<void> _uploadDirRecursive({
    required SftpClient sftp,
    required String localDir,
    required String remoteDir,
    required void Function(String, int, int) onProgress,
    required void Function(String) onFileSkipped,
    required bool Function() isCancelled,
  }) async {
    try { await sftp.mkdir(remoteDir); } catch (_) {}
    final entities = await Directory(localDir).list().toList();
    for (final entity in entities) {
      if (isCancelled()) return;
      final name = p.basename(entity.path);
      final remotePath = p.posix.join(remoteDir, name);
      if (entity is Directory) {
        await _uploadDirRecursive(
          sftp: sftp, localDir: entity.path, remoteDir: remotePath,
          onProgress: onProgress, onFileSkipped: onFileSkipped, isCancelled: isCancelled,
        );
      } else {
        try { await sftp.stat(remotePath); onFileSkipped(entity.path); continue; } catch (_) {}
        await _uploadFileWithProgress(sftp, entity.path, remotePath, onProgress);
      }
    }
  }

  Future<void> _uploadFileWithProgress(
    SftpClient sftp,
    String localPath,
    String remotePath,
    void Function(String, int, int) onProgress,
  ) async {
    final bytes = await File(localPath).readAsBytes();
    final total = bytes.length;
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    const chunkSize = 64 * 1024;
    int offset = 0;
    while (offset < total) {
      final end = (offset + chunkSize).clamp(0, total);
      await remoteFile.writeBytes(bytes.sublist(offset, end), offset: offset);
      offset = end;
      onProgress(localPath, offset, total);
    }
    await remoteFile.close();
  }

  Future<void> downloadDirectory({
    required Host remoteHost,
    required SftpEntry remoteDir,
    required String localDir,
    required void Function(String filePath, int bytes, int total) onProgress,
    required void Function(String filePath) onFileSkipped,
    required bool Function() isCancelled,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    try {
      await _downloadDirRecursive(
        sftp: sftp,
        remotePath: remoteDir.path,
        localDir: localDir,
        onProgress: onProgress,
        onFileSkipped: onFileSkipped,
        isCancelled: isCancelled,
      );
    } finally {
      sftp.close();
    }
  }

  Future<void> _downloadDirRecursive({
    required SftpClient sftp,
    required String remotePath,
    required String localDir,
    required void Function(String, int, int) onProgress,
    required void Function(String) onFileSkipped,
    required bool Function() isCancelled,
  }) async {
    final dest = Directory(p.join(localDir, p.posix.basename(remotePath)));
    if (!await dest.exists()) await dest.create(recursive: true);
    final items = await sftp.listdir(remotePath);
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      if (isCancelled()) return;
      final childRemote = p.posix.join(remotePath, item.filename);
      if (item.attr.isDirectory) {
        await _downloadDirRecursive(
          sftp: sftp, remotePath: childRemote, localDir: dest.path,
          onProgress: onProgress, onFileSkipped: onFileSkipped, isCancelled: isCancelled,
        );
      } else {
        final localPath = p.join(dest.path, item.filename);
        if (await File(localPath).exists()) { onFileSkipped(childRemote); continue; }
        await _downloadFileWithProgress(sftp, childRemote, localPath, item.attr.size ?? 0, onProgress);
      }
    }
  }

  Future<void> _downloadFileWithProgress(
    SftpClient sftp,
    String remotePath,
    String localPath,
    int totalBytes,
    void Function(String, int, int) onProgress,
  ) async {
    final remoteFile = await sftp.open(remotePath);
    const chunkSize = 64 * 1024;
    int offset = 0;
    final buffer = BytesBuilder();
    while (true) {
      final chunk = await remoteFile.readBytes(length: chunkSize, offset: offset);
      if (chunk.isEmpty) break;
      buffer.add(chunk);
      offset += chunk.length;
      onProgress(remotePath, offset, totalBytes > 0 ? totalBytes : offset);
    }
    await remoteFile.close();
    await File(localPath).writeAsBytes(buffer.toBytes());
  }
```

- [ ] **Step 3: Analyze**

```bash
cd app && flutter analyze lib/services/sftp_transfer_service.dart
```
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/sftp_transfer_service.dart
git commit -m "feat: add uploadDirectory/downloadDirectory with progress to SftpTransferService"
```

---

### Task 6: SftpEntryContextMenu widget

**Files:**
- Create: `app/lib/widgets/sftp_entry_context_menu.dart`

- [ ] **Step 1: Create the widget**

```dart
// app/lib/widgets/sftp_entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/sftp_entry.dart';

class SftpEntryContextMenu extends StatelessWidget {
  final SftpEntry entry;
  final Widget child;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const SftpEntryContextMenu({
    super.key,
    required this.entry,
    required this.child,
    required this.onOpen,
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
    showMenu<_Action>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
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
        case _Action.rename: onRename();
        case _Action.delete: onDelete();
        case _Action.copyPath: Clipboard.setData(ClipboardData(text: entry.path));
      }
    });
  }
}

enum _Action { open, rename, delete, copyPath }

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

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze lib/widgets/sftp_entry_context_menu.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/sftp_entry_context_menu.dart
git commit -m "feat: add SftpEntryContextMenu widget"
```

---

### Task 7: SftpTransferDialog widget

**Files:**
- Create: `app/lib/widgets/sftp_transfer_dialog.dart`

- [ ] **Step 1: Create the widget**

```dart
// app/lib/widgets/sftp_transfer_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sftp_transfer_item.dart';
import '../providers/sftp_transfer_provider.dart';

class SftpTransferDialog extends StatefulWidget {
  const SftpTransferDialog({super.key});

  @override
  State<SftpTransferDialog> createState() => _SftpTransferDialogState();
}

class _SftpTransferDialogState extends State<SftpTransferDialog> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<SftpTransferProvider>(
      builder: (context, tp, _) {
        final allDone = tp.totalCount > 0 && tp.completedCount == tp.totalCount;
        if (allDone && !_closing) {
          _closing = true;
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, tp),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: tp.overallProgress > 0 ? tp.overallProgress : null,
                      color: const Color(0xFF22C55E),
                      backgroundColor: const Color(0xFF252525),
                      minHeight: 6,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF2A2A2A), height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tp.items.length,
                    itemBuilder: (_, i) => _buildRow(tp.items[i]),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SftpTransferProvider tp) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, size: 15, color: Color(0xFF22C55E)),
          const SizedBox(width: 8),
          Text(
            'Transferring ${tp.completedCount} / ${tp.totalCount} files',
            style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton(
            onPressed: () { tp.cancel(); Navigator.of(context).pop(); },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF888888),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(SftpTransferItem item) {
    final (icon, color) = switch (item.status) {
      TransferStatus.done => (Icons.check_circle_outline, const Color(0xFF22C55E)),
      TransferStatus.skipped => (Icons.skip_next, const Color(0xFF888888)),
      TransferStatus.error => (Icons.error_outline, const Color(0xFFEF4444)),
      TransferStatus.inProgress => (Icons.swap_horiz, const Color(0xFF60A5FA)),
      TransferStatus.pending => (Icons.radio_button_unchecked, const Color(0xFF444444)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.fileName,
                style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          if (item.status == TransferStatus.inProgress)
            SizedBox(
              width: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.progress > 0 ? item.progress : null,
                  color: const Color(0xFF60A5FA),
                  backgroundColor: const Color(0xFF252525),
                  minHeight: 4,
                ),
              ),
            )
          else
            Text(_label(item), style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  String _label(SftpTransferItem item) => switch (item.status) {
    TransferStatus.done => item.totalBytes > 0 ? _fmt(item.totalBytes) : 'done',
    TransferStatus.skipped => 'skipped',
    TransferStatus.error => 'error',
    TransferStatus.pending => 'pending',
    TransferStatus.inProgress => '',
  };

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze lib/widgets/sftp_transfer_dialog.dart
```
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/sftp_transfer_dialog.dart
git commit -m "feat: add SftpTransferDialog with per-file and overall progress"
```

---

### Task 8: SftpPanel — checkbox + toolbar + context menu

**Files:**
- Modify: `app/lib/widgets/sftp_panel.dart`

- [ ] **Step 1: Add imports**

Add at the top of `app/lib/widgets/sftp_panel.dart` (after existing imports):

```dart
import '../services/sftp_file_ops_service.dart';
import 'sftp_entry_context_menu.dart';
```

- [ ] **Step 2: Replace `_buildPathBar`**

Replace the existing `_buildPathBar` method:

```dart
  Widget _buildPathBar(SftpPanelProvider prov) {
    final canRename = prov.selectedEntries.length == 1;
    final canDelete = prov.selectedEntries.isNotEmpty;
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF888888)),
            onPressed: () { prov.navigateUp(); _loadDirectory(prov.currentPath); },
            tooltip: 'Up',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          GestureDetector(
            onTap: widget.onChangeHost,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dns, size: 11, color: Color(0xFF22C55E)),
                  const SizedBox(width: 4),
                  Text('${widget.host!.username}@${widget.host!.host}',
                      style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontFamily: 'monospace')),
                  const SizedBox(width: 4),
                  const Icon(Icons.unfold_more, size: 11, color: Color(0xFF555555)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(prov.currentPath,
                style: const TextStyle(color: Color(0xFF888888), fontFamily: 'monospace', fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          _ToolbarBtn(icon: Icons.create_new_folder_outlined, tooltip: 'New folder',
              enabled: true, onTap: () => _showNewFolderDialog(prov)),
          _ToolbarBtn(icon: Icons.drive_file_rename_outline, tooltip: 'Rename',
              enabled: canRename, onTap: canRename ? () => _showRenameDialog(prov, prov.selectedEntries.first) : () {}),
          _ToolbarBtn(icon: Icons.delete_outline, tooltip: 'Delete',
              enabled: canDelete, onTap: canDelete ? () => _showDeleteConfirm(prov, prov.selectedEntries.toList()) : () {}),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF888888)),
            onPressed: () => _loadDirectory(prov.currentPath),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Replace `_buildContent` to add select-all header**

```dart
  Widget _buildContent(SftpPanelProvider prov) {
    if (prov.loadState == SftpPanelLoadState.loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (prov.loadState == SftpPanelLoadState.error) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 32),
          const SizedBox(height: 8),
          Text(prov.errorMessage ?? 'Error',
              style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
        ]),
      );
    }
    if (prov.entries.isEmpty) {
      return const Center(child: Text('Empty directory', style: TextStyle(color: Color(0xFF555555))));
    }
    return Column(
      children: [
        Container(
          color: const Color(0xFF141414),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: prov.isAllSelected,
                tristate: true,
                onChanged: (_) => prov.isAllSelected ? prov.deselectAll() : prov.selectAll(),
                side: const BorderSide(color: Color(0xFF444444)),
                activeColor: const Color(0xFF22C55E),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                prov.selectedEntries.isEmpty ? '${prov.entries.length} items' : '${prov.selectedEntries.length} selected',
                style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: prov.entries.length,
            itemBuilder: (_, i) => _buildEntryTile(prov.entries[i], prov),
          ),
        ),
      ],
    );
  }
```

- [ ] **Step 4: Replace `_buildEntryTile` to add checkbox + context menu**

```dart
  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return SftpEntryContextMenu(
      entry: entry,
      onOpen: () => _onEntryTap(entry),
      onRename: () => _showRenameDialog(prov, entry),
      onDelete: () => _showDeleteConfirm(prov, [entry]),
      child: Draggable<SftpEntry>(
        data: entry,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(entry.name, style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13)),
          ),
        ),
        child: InkWell(
          onTap: () => _onEntryTap(entry),
          child: Container(
            color: isSelected ? const Color(0xFF22C55E).withValues(alpha: 0.1) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => prov.toggleSelection(entry),
                  side: const BorderSide(color: Color(0xFF444444)),
                  activeColor: const Color(0xFF22C55E),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Icon(
                  entry.isDirectory ? Icons.folder : _fileIcon(entry.extension),
                  size: 16,
                  color: entry.isDirectory ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.name,
                      style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(entry.formattedSize,
                    style: const TextStyle(color: Color(0xFF555555), fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 5: Add dialog methods to `_SftpPanelState`**

```dart
  Future<void> _showNewFolderDialog(SftpPanelProvider prov) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New Folder', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Folder name', hintStyle: TextStyle(color: Color(0xFF555555)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A2A))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF22C55E))),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Create', style: TextStyle(color: Color(0xFF22C55E)))),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await context.read<SftpFileOpsService>().mkdir(widget.host!, '${prov.currentPath}/$name');
      _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create folder failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    }
  }

  Future<void> _showRenameDialog(SftpPanelProvider prov, SftpEntry entry) async {
    final ctrl = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Rename', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A2A))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF22C55E))),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Rename', style: TextStyle(color: Color(0xFF22C55E)))),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == entry.name || !mounted) return;
    final slash = entry.path.lastIndexOf('/');
    final parent = slash <= 0 ? '/' : entry.path.substring(0, slash);
    try {
      await context.read<SftpFileOpsService>().rename(widget.host!, entry.path, '$parent/$newName');
      prov.clearSelection();
      _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    }
  }

  Future<void> _showDeleteConfirm(SftpPanelProvider prov, List<SftpEntry> entries) async {
    final names = entries.map((e) => e.name).join(', ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontSize: 14)),
        content: Text('Delete "$names"?\nThis cannot be undone.', style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final ops = context.read<SftpFileOpsService>();
      for (final e in entries) { await ops.delete(widget.host!, e.path, isDirectory: e.isDirectory); }
      prov.clearSelection();
      _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    }
  }
```

- [ ] **Step 6: Add `_ToolbarBtn` class at end of file**

```dart
class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolbarBtn({required this.icon, required this.tooltip, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(icon, size: 15, color: enabled ? const Color(0xFF888888) : const Color(0xFF333333)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Analyze**

```bash
cd app && flutter analyze lib/widgets/sftp_panel.dart
```
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add app/lib/widgets/sftp_panel.dart
git commit -m "feat: add checkbox selection, toolbar, and context menu to SftpPanel"
```

---

### Task 9: DualPanelSftpScreen — 3-column layout + providers

**Files:**
- Modify: `app/lib/widgets/dual_panel_sftp_screen.dart`

- [ ] **Step 1: Replace file with 3-column version**

Replace the entire contents of `app/lib/widgets/dual_panel_sftp_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/local_entry.dart';
import '../models/sftp_entry.dart';
import '../models/sftp_transfer_item.dart';
import '../providers/host_provider.dart';
import '../providers/local_file_panel_provider.dart';
import '../providers/sftp_panel_provider.dart';
import '../providers/sftp_transfer_provider.dart';
import '../services/sftp_file_ops_service.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import 'local_file_panel.dart';
import 'sftp_panel.dart';
import 'sftp_transfer_dialog.dart';

class DualPanelSftpScreen extends StatefulWidget {
  final ValueNotifier<bool> connectionNotifier;

  const DualPanelSftpScreen({super.key, required this.connectionNotifier});

  @override
  State<DualPanelSftpScreen> createState() => _DualPanelSftpScreenState();
}

class _DualPanelSftpScreenState extends State<DualPanelSftpScreen> {
  Host? _hostA;
  Host? _hostB;
  late LocalFilePanelProvider _localProvider;
  late SftpPanelProvider _providerA;
  late SftpPanelProvider _providerB;
  late SftpTransferProvider _transferProvider;

  @override
  void initState() {
    super.initState();
    _localProvider = LocalFilePanelProvider();
    _providerA = SftpPanelProvider();
    _providerB = SftpPanelProvider();
    _transferProvider = SftpTransferProvider();
    widget.connectionNotifier.value = false;
  }

  @override
  void dispose() {
    widget.connectionNotifier.value = false;
    _localProvider.dispose();
    _providerA.dispose();
    _providerB.dispose();
    _transferProvider.dispose();
    super.dispose();
  }

  Future<Host?> _showHostPicker(Host? current) {
    final hosts = context.read<HostProvider>().allHosts;
    if (hosts.isEmpty) return Future.value(null);
    return showDialog<Host>(
      context: context,
      builder: (ctx) => _HostPickerDialog(hosts: hosts, current: current),
    );
  }

  Future<void> _pickHostA() async {
    final h = await _showHostPicker(_hostA);
    if (h != null && h.id != _hostA?.id) setState(() { _hostA = h; widget.connectionNotifier.value = true; });
  }

  Future<void> _pickHostB() async {
    final h = await _showHostPicker(_hostB);
    if (h != null && h.id != _hostB?.id) setState(() => _hostB = h);
  }

  void _showTransferDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider.value(
        value: _transferProvider,
        child: const SftpTransferDialog(),
      ),
    );
  }

  Future<void> _reloadA() async {
    if (!mounted || _hostA == null) return;
    _providerA.setLoadState(SftpPanelLoadState.loading);
    try {
      final entries = await context.read<SftpTransferService>().listDirectory(_hostA!, _providerA.currentPath);
      _providerA..setEntries(entries)..setLoadState(SftpPanelLoadState.loaded);
    } catch (e) { _providerA.setLoadState(SftpPanelLoadState.error, error: e.toString()); }
  }

  Future<void> _reloadB() async {
    if (!mounted || _hostB == null) return;
    _providerB.setLoadState(SftpPanelLoadState.loading);
    try {
      final entries = await context.read<SftpTransferService>().listDirectory(_hostB!, _providerB.currentPath);
      _providerB..setEntries(entries)..setLoadState(SftpPanelLoadState.loaded);
    } catch (e) { _providerB.setLoadState(SftpPanelLoadState.error, error: e.toString()); }
  }

  // ── Local → RemoteA ───────────────────────────────────

  Future<void> _upload() async {
    final host = _hostA;
    if (host == null) return;
    final selected = _localProvider.selectedEntries.toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final remoteDir = _providerA.currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i];
        final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        if (entry.isDirectory) {
          await service.uploadDirectory(
            localDir: entry.path, remoteHost: host,
            remoteDir: '$remoteDir/${entry.name}',
            onProgress: (_, bytes, total) => _transferProvider.updateItem(item.id, bytesTransferred: bytes),
            onFileSkipped: (_) => _transferProvider.updateItem(item.id, status: TransferStatus.skipped),
            isCancelled: () => _transferProvider.isCancelled,
          );
        } else {
          await service.copyLocalToRemote(localPath: entry.path, remoteHost: host, remoteDir: remoteDir);
          _transferProvider.updateItem(item.id, bytesTransferred: entry.size);
        }
        _transferProvider.updateItem(item.id, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    } finally { await _reloadA(); }
  }

  // ── RemoteA → Local ───────────────────────────────────

  Future<void> _download() async {
    final host = _hostA;
    if (host == null) return;
    final selected = _providerA.selectedEntries.toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final localDir = _localProvider.currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.download)..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i];
        final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        if (entry.isDirectory) {
          await service.downloadDirectory(
            remoteHost: host, remoteDir: entry, localDir: localDir,
            onProgress: (_, bytes, total) => _transferProvider.updateItem(item.id, bytesTransferred: bytes),
            onFileSkipped: (_) {},
            isCancelled: () => _transferProvider.isCancelled,
          );
        } else {
          await service.copyRemoteToLocal(remoteHost: host, remoteEntry: entry, localDir: localDir);
          _transferProvider.updateItem(item.id, bytesTransferred: entry.size);
        }
        _transferProvider.updateItem(item.id, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    } finally { await _localProvider.reload(); }
  }

  // ── RemoteA → RemoteB ─────────────────────────────────

  Future<void> _copyAtoB() async {
    final hostA = _hostA; final hostB = _hostB;
    if (hostA == null || hostB == null) return;
    final selected = _providerA.selectedEntries.where((e) => !e.isDirectory).toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final destDir = _providerB.currentPath;

    final items = [for (final e in selected) SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)..totalBytes = e.size];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i]; final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        final tmp = await service.downloadToTemp(hostA, entry);
        if (tmp != null) await service.copyLocalToRemote(localPath: tmp, remoteHost: hostB, remoteDir: destDir);
        _transferProvider.updateItem(item.id, bytesTransferred: entry.size, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copy failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    } finally { await _reloadB(); }
  }

  // ── RemoteB → RemoteA ─────────────────────────────────

  Future<void> _copyBtoA() async {
    final hostA = _hostA; final hostB = _hostB;
    if (hostA == null || hostB == null) return;
    final selected = _providerB.selectedEntries.where((e) => !e.isDirectory).toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final destDir = _providerA.currentPath;

    final items = [for (final e in selected) SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)..totalBytes = e.size];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i]; final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        final tmp = await service.downloadToTemp(hostB, entry);
        if (tmp != null) await service.copyLocalToRemote(localPath: tmp, remoteHost: hostA, remoteDir: destDir);
        _transferProvider.updateItem(item.id, bytesTransferred: entry.size, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copy failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
    } finally { await _reloadA(); }
  }

  // ── Drag & Drop ───────────────────────────────────────

  Future<void> _onLocalDroppedOnRemote(LocalEntry entry) async {
    if (_hostA == null || entry.isDirectory) return;
    _localProvider.selectOnly(entry);
    await _upload();
  }

  Future<void> _onRemoteDroppedOnLocal(SftpEntry entry) async {
    if (_hostA == null || entry.isDirectory) return;
    _providerA.toggleSelection(entry);
    await _download();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (ctx) => SftpTransferService(ctx.read<SshService>())),
        Provider(create: (ctx) => SftpFileOpsService(ctx.read<SshService>())),
        ChangeNotifierProvider.value(value: _transferProvider),
      ],
      child: ListenableBuilder(
        listenable: Listenable.merge([_localProvider, _providerA, _providerB]),
        builder: (context, _) => Column(
          children: [
            Consumer<SftpTransferProvider>(
              builder: (_, tp, __) => tp.isTransferring
                  ? LinearProgressIndicator(
                      value: tp.overallProgress > 0 ? tp.overallProgress : null,
                      color: const Color(0xFF22C55E),
                      backgroundColor: const Color(0xFF1A1A1A),
                      minHeight: 2)
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Row(
                children: [
                  // Local
                  Expanded(
                    child: DragTarget<SftpEntry>(
                      onAcceptWithDetails: (d) => _onRemoteDroppedOnLocal(d.data),
                      builder: (_, candidates, __) => Container(
                        decoration: BoxDecoration(
                          border: candidates.isNotEmpty
                              ? Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4), width: 2)
                              : null,
                        ),
                        child: LocalFilePanel(provider: _localProvider),
                      ),
                    ),
                  ),
                  // Bar: Local ↔ RemoteA
                  _TransferBar(
                    canLeft: _hostA != null && _providerA.selectedEntries.isNotEmpty,
                    canRight: _hostA != null && _localProvider.selectedEntries.isNotEmpty,
                    onLeft: _download,
                    onRight: _upload,
                  ),
                  // RemoteA
                  Expanded(
                    child: DragTarget<LocalEntry>(
                      onAcceptWithDetails: (d) => _onLocalDroppedOnRemote(d.data),
                      builder: (_, candidates, __) => Container(
                        decoration: BoxDecoration(
                          border: candidates.isNotEmpty
                              ? Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4), width: 2)
                              : null,
                        ),
                        child: SftpPanel(
                          key: ValueKey('ra_${_hostA?.id}'),
                          host: _hostA, panelId: 'remote_a',
                          provider: _providerA, onChangeHost: _pickHostA,
                        ),
                      ),
                    ),
                  ),
                  // Bar: RemoteA ↔ RemoteB
                  _TransferBar(
                    canLeft: _hostA != null && _hostB != null && _providerB.selectedEntries.any((e) => !e.isDirectory),
                    canRight: _hostA != null && _hostB != null && _providerA.selectedEntries.any((e) => !e.isDirectory),
                    onLeft: _copyBtoA,
                    onRight: _copyAtoB,
                  ),
                  // RemoteB
                  Expanded(
                    child: SftpPanel(
                      key: ValueKey('rb_${_hostB?.id}'),
                      host: _hostB, panelId: 'remote_b',
                      provider: _providerB, onChangeHost: _pickHostB,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferBar extends StatelessWidget {
  final bool canLeft;
  final bool canRight;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _TransferBar({required this.canLeft, required this.canRight, required this.onLeft, required this.onRight});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      color: const Color(0xFF111111),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Btn(icon: Icons.arrow_forward, tooltip: 'Copy →', enabled: canRight, onTap: onRight),
          const SizedBox(height: 8),
          _Btn(icon: Icons.arrow_back, tooltip: 'Copy ←', enabled: canLeft, onTap: onLeft),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _Btn({required this.icon, required this.tooltip, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFF22C55E).withValues(alpha: 0.12) : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: enabled ? const Color(0xFF22C55E).withValues(alpha: 0.3) : const Color(0xFF252525)),
          ),
          child: Icon(icon, size: 14, color: enabled ? const Color(0xFF22C55E) : const Color(0xFF333333)),
        ),
      ),
    );
  }
}

class _HostPickerDialog extends StatelessWidget {
  final List<Host> hosts;
  final Host? current;

  const _HostPickerDialog({required this.hosts, required this.current});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
              child: Row(children: [
                const Icon(Icons.dns_outlined, size: 15, color: Color(0xFF888888)),
                const SizedBox(width: 8),
                const Text('Select Remote Host',
                    style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 14, color: Color(0xFF555555))),
              ]),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: hosts.length,
                itemBuilder: (_, i) {
                  final h = hosts[i];
                  final active = h.id == current?.id;
                  return InkWell(
                    onTap: () => Navigator.pop(context, h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: active ? const Color(0xFF22C55E).withValues(alpha: 0.08) : Colors.transparent,
                      child: Row(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.dns, size: 14, color: Color(0xFF22C55E)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.label, style: TextStyle(
                              color: active ? const Color(0xFF22C55E) : const Color(0xFFD4D4D4),
                              fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                            Text('${h.username}@${h.host}:${h.port}',
                                style: const TextStyle(color: Color(0xFF555555), fontSize: 11, fontFamily: 'monospace')),
                          ],
                        )),
                        if (active) const Icon(Icons.check, size: 14, color: Color(0xFF22C55E)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze lib/widgets/dual_panel_sftp_screen.dart
```
Expected: No issues.

- [ ] **Step 3: Run full test suite**

```bash
cd app && flutter test
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/dual_panel_sftp_screen.dart
git commit -m "feat: 3-column SFTP layout with RemoteB panel, SftpFileOpsService, and progress dialog"
```

---

### Task 10: Final analyze + smoke test

- [ ] **Step 1: Full analyze**

```bash
cd app && flutter analyze
```
Expected: No issues.

- [ ] **Step 2: Run all tests**

```bash
cd app && flutter test
```
Expected: All tests pass.

- [ ] **Step 3: Build to confirm no compile errors**

```bash
cd app && flutter build macos --debug 2>&1 | tail -5
```
Expected: `Build complete.`

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete SFTP enhancements (file ops, checkbox, folder transfer, progress, 3-column)"
```
