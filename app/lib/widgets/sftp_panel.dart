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
import '../util/app_launcher.dart';
import '../util/file_mode.dart';
import 'code_editor_screen.dart';
import 'path_breadcrumb.dart';
import 'entry_context_menu.dart';
import 'permissions_dialog.dart';

class SftpPanel extends StatefulWidget {
  final Host? host;
  final String panelId;
  final SftpPanelProvider provider;
  final VoidCallback onChangeHost;

  /// Directory to load on mount. The dual-panel screen passes the last path
  /// browsed on this host so switching a slot's source away and back resumes
  /// where the user left off.
  final String initialPath;

  /// Copies [entry] into the opposite panel's current directory (wired by
  /// the dual-panel screen). Null when the panel is used standalone.
  final void Function(SftpEntry entry)? onCopyToTarget;

  /// Why copy-to-target is unavailable for [entry] (null = available).
  final String? Function(SftpEntry entry)? copyToTargetBlockReason;

  const SftpPanel({
    super.key,
    required this.host,
    required this.panelId,
    required this.provider,
    required this.onChangeHost,
    this.initialPath = '/',
    this.onCopyToTarget,
    this.copyToTargetBlockReason,
  });

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.host != null) {
      // Deferred: initState runs inside the parent ListenableBuilder's build
      // (slot source switch recreates this panel mid-build), and provider
      // notifications during build are dropped by the framework.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDirectory(widget.initialPath);
      });
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

  // No didUpdateWidget host handling: the dual-panel screen keys this panel
  // by host id, so a source switch always recreates the State and initState
  // performs the (possibly remembered) initial load.

  /// Loads [path] and records it in the back/forward history (via setPath).
  Future<void> _loadDirectory(String path) async {
    if (widget.host == null) return;
    widget.provider.setPath(path);
    await _fetchEntries(path);
  }

  /// Lists [path] into the provider without touching the history — used by
  /// _loadDirectory and by back/forward, which move the history cursor
  /// themselves.
  Future<void> _fetchEntries(String path) async {
    final host = widget.host;
    if (host == null) return;
    widget.provider.setLoadState(SftpPanelLoadState.loading);
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
            _buildHeader(prov),
            if (prov.filterVisible) _buildFilterBar(prov),
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

  /// Header matching the local panel: source chip + Filter + Actions menu.
  Widget _buildHeader(SftpPanelProvider prov) {
    final canRename = prov.selectedEntries.length == 1;
    final canDelete = prov.selectedEntries.isNotEmpty;
    return Container(
      height: 40,
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // The chip+badge group owns ALL free row space (Expanded) so
          // Filter/Actions always hug the right edge; the chip itself is
          // loose (Flexible) inside and ellipsizes when the label is long.
          // (Flexible chip + Spacer split the free space instead, leaving a
          // gap to the right of Actions on wide panels.)
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: GestureDetector(
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
                          Flexible(
                            child: Text(widget.host!.label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF22C55E), fontSize: 12)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.unfold_more, size: 11, color: Color(0xFF555555)),
                        ],
                      ),
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
              ],
            ),
          ),
          _HeaderButton(
            label: 'Filter',
            active: prov.filterVisible,
            onTap: prov.toggleFilterVisible,
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFF2A2A2A))),
            tooltip: '',
            offset: const Offset(0, 36),
            onSelected: (v) {
              if (v == 'new_file') _showNewFileDialog(prov);
              if (v == 'new_folder') _showNewFolderDialog(prov);
              if (v == 'rename') _showRenameDialog(prov, prov.selectedEntries.first);
              if (v == 'delete') _showDeleteConfirm(prov, prov.selectedEntries.toList());
            },
            itemBuilder: (_) => [
              _menuItem('new_file', Icons.note_add_outlined, 'New File'),
              _menuItem('new_folder', Icons.create_new_folder_outlined, 'New Folder'),
              _menuItem('rename', Icons.drive_file_rename_outline, 'Rename',
                  enabled: canRename),
              _menuItem('delete', Icons.delete_outline, 'Delete',
                  enabled: canDelete, isDestructive: true),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Text('Actions',
                    style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 12)),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF888888)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {bool enabled = true, bool isDestructive = false}) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(children: [
        Icon(icon,
            size: 14,
            color: isDestructive
                ? Colors.red
                : enabled
                    ? const Color(0xFFD4D4D4)
                    : const Color(0xFF444444)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: isDestructive
                    ? Colors.red
                    : enabled
                        ? const Color(0xFFD4D4D4)
                        : const Color(0xFF444444))),
      ]),
    );
  }

  Widget _buildFilterBar(SftpPanelProvider prov) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        autofocus: true,
        style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Filter by name…',
          hintStyle: const TextStyle(color: Color(0xFF444444), fontSize: 13),
          prefixIcon:
              const Icon(Icons.search, size: 15, color: Color(0xFF555555)),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF22C55E))),
        ),
        onChanged: prov.setFilterQuery,
      ),
    );
  }

  Widget _buildPathBar(SftpPanelProvider prov) {
    return Container(
      height: 34,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left,
                size: 16,
                color: prov.canGoBack
                    ? const Color(0xFF888888)
                    : const Color(0xFF333333)),
            onPressed: prov.canGoBack
                ? () {
                    prov.goBack();
                    _fetchEntries(prov.currentPath);
                  }
                : null,
            tooltip: 'Back',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 16,
                color: prov.canGoForward
                    ? const Color(0xFF888888)
                    : const Color(0xFF333333)),
            onPressed: prov.canGoForward
                ? () {
                    prov.goForward();
                    _fetchEntries(prov.currentPath);
                  }
                : null,
            tooltip: 'Forward',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          const SizedBox(width: 2),
          // Breadcrumb gets the remaining row width (it was squeezed to zero
          // when it shared the row with the host chip and toolbar buttons).
          Expanded(
            child: PathBreadcrumb(
              crumbs: posixCrumbs(prov.currentPath),
              onNavigate: _loadDirectory,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 13, color: Color(0xFF555555)),
            onPressed: () => _loadDirectory(prov.currentPath),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
    final entries = prov.filteredEntries;
    if (entries.isEmpty) {
      // Distinguish a genuinely empty directory from a filter with no hits
      // (mirrors LocalFilePanel).
      return Center(
        child: Text(
          prov.filterQuery.isNotEmpty ? 'No matches' : 'Empty directory',
          style: const TextStyle(color: Color(0xFF555555)),
        ),
      );
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
                prov.selectedEntries.isEmpty ? '${entries.length} items' : '${prov.selectedEntries.length} selected',
                style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (_, i) => _buildEntryTile(entries[i], prov),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return EntryContextMenu(
      path: entry.path,
      isDirectory: entry.isDirectory,
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
              final appPath = await pickApplication();
              if (appPath != null && mounted) {
                await _openWithApp(entry, appPath);
              }
            },
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
      if (mounted) _loadDirectory(prov.currentPath);
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
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rename failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    }
  }

  Future<void> _showPermissionsDialog(
      SftpPanelProvider prov, SftpEntry entry) async {
    // Listings may legally omit permissions (SFTP v3) — stat() as fallback;
    // if that fails too, pass null so the dialog warns and gates Apply
    // instead of silently opening at 000.
    var initialMode = entry.mode;
    if (initialMode == null) {
      try {
        initialMode = await context
            .read<SftpFileOpsService>()
            .statMode(widget.host!, entry.path);
      } catch (_) {}
      if (!mounted) return;
    }
    final result = await showDialog<({int mode, bool recursive})>(
      context: context,
      builder: (_) => PermissionsDialog(
        entryName: entry.name,
        initialMode: initialMode,
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
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('chmod ${modeToOctal(result.mode)} failed: $e'),
            backgroundColor: const Color(0xFF2A1A1A)));
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
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    }
  }
}

class _HeaderButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderButton(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF22C55E).withValues(alpha: 0.12)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: active
                  ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                  : const Color(0xFF2A2A2A)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? const Color(0xFF22C55E)
                : const Color(0xFFD4D4D4),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

