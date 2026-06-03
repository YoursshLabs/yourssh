import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/app_discovery_service.dart';
import '../services/external_edit_service.dart';
import '../services/sftp_file_inspector.dart';
import '../services/sftp_transfer_service.dart';
import '../services/sftp_file_ops_service.dart';
import 'code_editor_screen.dart';
import 'sftp_entry_context_menu.dart';

class SftpPanel extends StatefulWidget {
  final Host? host;
  final String panelId;
  final SftpPanelProvider provider;
  final VoidCallback onChangeHost;

  const SftpPanel({
    super.key,
    required this.host,
    required this.panelId,
    required this.provider,
    required this.onChangeHost,
  });

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.host != null) {
      _loadDirectory('/');
    }
    // Wired once: the upload callbacks fire from the external-edit mtime
    // watcher long after the triggering open, so resolve the messenger at
    // fire time (and only while this panel is still mounted) instead of
    // capturing one per open. Not cleared in dispose — the mounted guard
    // makes stale closures inert, and clearing could clobber a newer panel's
    // wiring.
    final service = context.read<ExternalEditService>();
    service.onUploaded = (name) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Uploaded $name to server'),
          duration: const Duration(seconds: 2)));
    };
    service.onUploadError = (name, e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload of $name failed: $e'),
          backgroundColor: const Color(0xFF2A1A1A)));
    };
  }

  @override
  void didUpdateWidget(SftpPanel old) {
    super.didUpdateWidget(old);
    if (old.host?.id != widget.host?.id && widget.host != null) {
      widget.provider
        ..setLoadState(SftpPanelLoadState.idle)
        ..setPath('/');
      _loadDirectory('/');
    }
  }

  Future<void> _loadDirectory(String path) async {
    final host = widget.host;
    if (host == null) return;
    widget.provider.setLoadState(SftpPanelLoadState.loading);
    widget.provider.setPath(path);
    try {
      final service = context.read<SftpTransferService>();
      final entries = await service.listDirectory(host, path);
      widget.provider.setEntries(entries);
      widget.provider.setLoadState(SftpPanelLoadState.loaded);
    } catch (e) {
      widget.provider.setLoadState(SftpPanelLoadState.error,
          error: e.toString());
    }
  }

  void _onEntryTap(SftpEntry entry) {
    if (entry.isDirectory) {
      _loadDirectory(entry.path);
      return;
    }
    final reason = editBlockReason(entry);
    if (reason != EditBlockReason.none) {
      _confirmOpenExternal(entry, reason);
    } else {
      _openEditor(entry);
    }
  }

  Future<void> _openViewer(SftpEntry entry) {
    final service = context.read<SftpTransferService>();
    final externalEdit = context.read<ExternalEditService>();
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            Provider<SftpTransferService>.value(value: service),
            Provider<ExternalEditService>.value(value: externalEdit),
          ],
          child: CodeEditorScreen(
              host: widget.host!, entry: entry, readOnly: true),
        ),
      ),
    );
  }

  Future<void> _openEditor(SftpEntry entry) {
    final service = context.read<SftpTransferService>();
    final externalEdit = context.read<ExternalEditService>();
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiProvider(
          providers: [
            Provider<SftpTransferService>.value(value: service),
            Provider<ExternalEditService>.value(value: externalEdit),
          ],
          child: CodeEditorScreen(host: widget.host!, entry: entry),
        ),
      ),
    );
  }

  /// File failed the pre-download check (binary extension / too large):
  /// offer to open it with the OS default application instead.
  Future<void> _confirmOpenExternal(
      SftpEntry entry, EditBlockReason reason) async {
    final why = switch (reason) {
      EditBlockReason.binaryExtension => 'This looks like a binary file.',
      EditBlockReason.tooLarge =>
        'This file is too large for the in-app editor.',
      EditBlockReason.none => '',
    };
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Cannot edit in-app',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
        content: Text(
          '$why\nOpen "${entry.name}" with an external application instead? '
          'Changes saved there are uploaded back automatically.',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF888888)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open externally',
                  style: TextStyle(color: Color(0xFF22C55E)))),
        ],
      ),
    );
    if (open == true && mounted) await _openExternal(entry);
  }

  Future<void> _openExternal(SftpEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<ExternalEditService>();
    try {
      await service.openExternal(widget.host!, entry);
      messenger.showSnackBar(SnackBar(
          content: Text('Opened ${entry.name} — watching for changes'),
          duration: const Duration(seconds: 2)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Open externally failed: $e'),
          backgroundColor: const Color(0xFF2A1A1A)));
    }
  }

  Future<void> _openWithApp(SftpEntry entry, String appPath) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = context.read<ExternalEditService>();
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

  Future<String?> _pickApp() async {
    if (Platform.isMacOS) {
      const typeGroup =
          XTypeGroup(label: 'Applications', extensions: ['app']);
      final file = await openFile(
          acceptedTypeGroups: [typeGroup],
          initialDirectory: '/Applications');
      return file?.path;
    }
    if (Platform.isWindows) {
      const typeGroup =
          XTypeGroup(label: 'Executables', extensions: ['exe']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      return file?.path;
    }
    final file = await openFile();
    return file?.path;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.host == null) {
      return _buildEmptyState();
    }
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<SftpPanelProvider>(
        builder: (context, prov, _) => Column(
          children: [
            _buildPathBar(prov),
            Expanded(child: _buildContent(prov)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder_outlined,
                size: 32, color: Color(0xFF444444)),
          ),
          const SizedBox(height: 16),
          const Text('Connect to host',
              style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Start by connecting to a saved host\nto manage your files with SFTP.',
            style: TextStyle(color: Color(0xFF555555), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: widget.onChangeHost,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: const Text('Select host',
                  style: TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

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
          if (widget.host!.sftpMode != SftpMode.normal) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'SFTP runs elevated on this host',
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('root',
                    style: TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace')),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Expanded(
            child: Text(prov.currentPath,
                style: const TextStyle(color: Color(0xFF888888), fontFamily: 'monospace', fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          _ToolbarBtn(icon: Icons.note_add_outlined, tooltip: 'New file',
              enabled: true, onTap: () => _showNewFileDialog(prov)),
          _ToolbarBtn(icon: Icons.create_new_folder_outlined, tooltip: 'New folder',
              enabled: true, onTap: () => _showNewFolderDialog(prov)),
          _ToolbarBtn(icon: Icons.drive_file_rename_outline, tooltip: 'Rename',
              enabled: canRename, onTap: canRename ? () => _showRenameDialog(prov, prov.selectedEntries.first) : null),
          _ToolbarBtn(icon: Icons.delete_outline, tooltip: 'Delete',
              enabled: canDelete, onTap: canDelete ? () => _showDeleteConfirm(prov, prov.selectedEntries.toList()) : null),
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

  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return SftpEntryContextMenu(
      entry: entry,
      onOpen: () => _onEntryTap(entry),
      onView: entry.isDirectory ? null : () => _openViewer(entry),
      onEdit: entry.isDirectory ? null : () => _openEditor(entry),
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

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'go' ||
      'rs' ||
      'c' ||
      'cpp' =>
        Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }

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
      final newPath = prov.currentPath == '/' ? '/$name' : '${prov.currentPath}/$name';
      await context.read<SftpFileOpsService>().mkdir(widget.host!, newPath);
      _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Create folder failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    }
  }

  Future<void> _showNewFileDialog(SftpPanelProvider prov) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('New File', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888)))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Create', style: TextStyle(color: Color(0xFF22C55E)))),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final remotePath = prov.currentPath == '/' ? '/$name' : '${prov.currentPath}/$name';
      await context.read<SftpFileOpsService>().createFile(widget.host!, remotePath);
      final entry = SftpEntry(
        name: name,
        path: remotePath,
        isDirectory: false,
        size: 0,
        modifiedAt: DateTime.now(),
      );
      if (!mounted) return;
      await _openEditor(entry);
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Create file failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rename failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    }
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onTap;

  const _ToolbarBtn({required this.icon, required this.tooltip, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(icon, size: 15, color: enabled ? const Color(0xFF888888) : const Color(0xFF333333)),
        ),
      ),
    );
  }
}

