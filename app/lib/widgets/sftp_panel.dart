import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../providers/host_provider.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/app_discovery_service.dart';
import '../services/external_edit_service.dart';
import '../services/sftp_file_inspector.dart';
import '../services/sftp_transfer_service.dart';
import '../services/sftp_file_ops_service.dart';
import '../util/app_launcher.dart';
import '../util/file_mode.dart';
import 'code_editor_screen.dart';
import '../util/entry_sort.dart';
import 'entry_context_menu.dart';
import 'file_panel_chrome.dart';
import 'path_breadcrumb.dart';
import 'permissions_dialog.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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

class _SftpPanelState extends State<SftpPanel>
    with MidnightRefresh {
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
      showYsToast(context, 'Uploaded $name to server',
          kind: YsToastKind.success, duration: const Duration(seconds: 2));
    };
    service.onUploadError = (name, e) {
      if (!mounted) return;
      AppSnack.error(context, 'Upload of $name failed: $e');
    };
  }

  @override
  void dispose() {
    EntryContextMenu.dismissOwnedBy(context);
    super.dispose();
  }

  // No didUpdateWidget host handling: the dual-panel screen keys this panel
  // by host id, so a source switch always recreates the State and initState
  // performs the (possibly remembered) initial load.

  /// Loads [path] and records it in the back/forward history (via setPath).
  Future<void> _loadDirectory(String path) async {
    if (widget.host == null) return;
    final normalized = _normalizeRemotePath(path);
    widget.provider.setPath(normalized);
    await _fetchEntries(normalized);
  }

  /// Cleans up a path typed into the breadcrumb editor. Remote paths are
  /// always absolute POSIX, so a relative entry resolves against root and a
  /// trailing slash is dropped (except root) to keep derived child paths from
  /// doubling up. Crumb/entry paths are already canonical, so this is a no-op
  /// for them.
  String _normalizeRemotePath(String input) {
    var path = input.trim();
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
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
    final open = await showYsDialog<bool>(
      context,
      builder: (ctx) => YsDialog(
        title: 'Cannot edit in-app',
        body: Text(
          '$why\nOpen "${entry.name}" with an external application instead? '
          'Changes saved there are uploaded back automatically.',
        ),
        actions: [
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FButton(
            variant: FButtonVariant.primary,
            onPress: () => Navigator.pop(ctx, true),
            child: const Text('Open externally'),
          ),
        ],
      ),
    );
    if (open == true && mounted) await _openExternal(entry);
  }

  Future<void> _openExternal(SftpEntry entry) async {
    final service = context.read<ExternalEditService>();
    try {
      await service.openExternal(widget.host!, entry);
      if (!mounted) return;
      showYsToast(context, 'Opened ${entry.name} — watching for changes',
          duration: const Duration(seconds: 2));
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Open externally failed: $e');
    }
  }

  Future<void> _openWithApp(SftpEntry entry, String appPath) async {
    final service = context.read<ExternalEditService>();
    try {
      await service.openExternalWith(widget.host!, entry, appPath);
      if (!mounted) return;
      showYsToast(context, 'Opened ${entry.name} — watching for changes',
          duration: const Duration(seconds: 2));
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Open with failed: $e');
    }
  }

  /// Columns of the file table. Kept for the day so unchanged rows are
  /// reused across selection changes; cells depend only on the entry (and
  /// the date, through the "Today" labels).
  List<YsColumn<SftpEntry>> get _columns => dayColumns(() => [
    YsColumn<SftpEntry>(
      id: EntrySortColumn.name,
      label: 'Name',
      flex: 5,
      sortable: true,
      cell: (_, e) => FileNameCell(
          name: e.name, isDirectory: e.isDirectory, extension: e.extension),
    ),
    YsColumn<SftpEntry>(
      id: EntrySortColumn.modified,
      label: 'Modified',
      width: 120,
      sortable: true,
      minTableWidth: 400,
      cell: (_, e) => FileMetaCell(formatEntryDate(e.modifiedAt)),
    ),
    YsColumn<SftpEntry>(
      id: EntrySortColumn.size,
      label: 'Size',
      width: 70,
      sortable: true,
      numeric: true,
      cell: (_, e) => FileMetaCell(e.formattedSize),
    ),
    YsColumn<SftpEntry>(
      id: 'permissions',
      label: 'Permissions',
      width: 90,
      minTableWidth: 500,
      cell: (_, e) => FileMetaCell(
          formatEntryMode(e.mode, isDirectory: e.isDirectory),
          mono: true),
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    if (widget.host == null) {
      return _buildEmptyState();
    }
    // Resolved from HostProvider, not widget.host: the panel's snapshot
    // predates any host edit, so a switch to Sudo/Custom mode never lit the
    // badge (SshService.openSftp resolves the live mode the same way). Read
    // here — `select` is only legal in a real build method, not in the
    // Consumer builder below.
    bool elevated;
    try {
      elevated = context.select<HostProvider, bool>((hp) =>
          (hp.byId(widget.host!.id) ?? widget.host!).sftpMode !=
          SftpMode.normal);
    } on ProviderNotFoundException {
      // Tests pump this panel without a HostProvider.
      elevated = widget.host!.sftpMode != SftpMode.normal;
    }
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<SftpPanelProvider>(
        builder: (context, prov, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(prov, elevated: elevated),
            if (prov.filterVisible)
              FilePanelFilterBar(onChanged: prov.setFilterQuery),
            _buildPathBar(prov),
            Expanded(child: _buildContent(prov)),
            if (prov.loadState == SftpPanelLoadState.loaded &&
                prov.filteredEntries.isNotEmpty)
              FilePanelFooter(prov.selectedEntries.isEmpty
                  ? '${prov.filteredEntries.length} items'
                  : '${prov.selectedEntries.length} selected'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return YsEmptyState(
      icon: FLucideIcons.folder,
      title: 'Connect to host',
      message:
          'Start by connecting to a saved host\nto manage your files with SFTP.',
      action: FButton(
        variant: .outline,
        size: .sm,
        mainAxisSize: MainAxisSize.min,
        onPress: widget.onChangeHost,
        child: const Text('Select host'),
      ),
    );
  }

  /// Header matching the local panel: source chip + Filter + Actions menu.
  /// [elevated] comes from the live host (see [build]), not widget.host.
  Widget _buildHeader(SftpPanelProvider prov, {required bool elevated}) {
    final selected = prov.selectedEntries;
    return FilePanelHeader(
      sourceIcon: FLucideIcons.server,
      sourceLabel: widget.host!.label,
      onChangeSource: widget.onChangeHost,
      badge: elevated
          ? const Tooltip(
              message: 'SFTP runs elevated on this host',
              child: YsStatusBadge('root', status: YsStatus.error),
            )
          : null,
      filterActive: prov.filterVisible,
      onToggleFilter: prov.toggleFilterVisible,
      actions: [
        FilePanelAction('New File', FLucideIcons.filePlus,
            () => _showNewFileDialog(prov)),
        FilePanelAction('New Folder', FLucideIcons.folderPlus,
            () => _showNewFolderDialog(prov)),
        FilePanelAction('Rename', FLucideIcons.pencilLine,
            () => _showRenameDialog(prov, prov.selectedEntries.first),
            enabled: selected.length == 1),
        FilePanelAction('Delete', FLucideIcons.trash2,
            () => _showDeleteConfirm(prov, prov.selectedEntries.toList()),
            enabled: selected.isNotEmpty, destructive: true),
      ],
    );
  }

  Widget _buildPathBar(SftpPanelProvider prov) {
    return FilePanelPathBar(
      canGoBack: prov.canGoBack,
      canGoForward: prov.canGoForward,
      onBack: () {
        prov.goBack();
        _fetchEntries(prov.currentPath);
      },
      onForward: () {
        prov.goForward();
        _fetchEntries(prov.currentPath);
      },
      onRefresh: () => _loadDirectory(prov.currentPath),
      breadcrumb: PathBreadcrumb(
        crumbs: posixCrumbs(prov.currentPath),
        onNavigate: _loadDirectory,
        editablePath: prov.currentPath,
      ),
    );
  }

  Widget _buildContent(SftpPanelProvider prov) {
    // The table stays mounted through loading / error / empty listings so
    // it keeps keyboard focus across a folder change.
    final loaded = prov.loadState != SftpPanelLoadState.loading &&
        prov.loadState != SftpPanelLoadState.error;
    final entries = loaded ? prov.filteredEntries : const <SftpEntry>[];
    return YsFileTable<SftpEntry>(
      rows: entries,
      columns: _columns,
      selected: prov.selectedEntries,
      sort: YsSort(prov.sortColumn, ascending: prov.sortAscending),
      onSort: (s) => prov.setSort(s.column, ascending: s.ascending),
      onSelect: prov.select,
      onSelectAll: (all) => all ? prov.selectAll() : prov.deselectAll(),
      // Double-click / Enter: the menu's Open (folders navigate in, files
      // open in the editor or, when refused, externally).
      onOpen: _onEntryTap,
      onContextMenu: (entry, position) =>
          _entryMenu(prov, entry).show(context, position),
      rowKey: (e) => e.path,
      emptyState: switch (prov.loadState) {
        SftpPanelLoadState.loading => const Center(child: FCircularProgress()),
        SftpPanelLoadState.error =>
          FilePanelError(prov.errorMessage ?? 'Error'),
        // Distinguish a genuinely empty directory from a filter with no
        // hits (mirrors LocalFilePanel).
        _ => FilePanelMessage(
            prov.filterQuery.isNotEmpty ? 'No matches' : 'Empty directory'),
      },
      checkboxes: true,
      draggable: true,
      rowLabel: (e) => e.name,
    );
  }

  /// The shared entry context menu for [entry].
  EntryContextMenu _entryMenu(SftpPanelProvider prov, SftpEntry entry) {
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
    );
  }

  Future<void> _showNewFolderDialog(SftpPanelProvider prov) async {
    final name = (await showFileNameDialog(context,
            title: 'New Folder', hint: 'Folder name', confirmLabel: 'Create'))
        ?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final newPath = prov.currentPath == '/' ? '/$name' : '${prov.currentPath}/$name';
      await context.read<SftpFileOpsService>().mkdir(widget.host!, newPath);
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'Create folder failed: $e');
      }
    }
  }

  Future<void> _showNewFileDialog(SftpPanelProvider prov) async {
    final name = (await showFileNameDialog(context,
            title: 'New File', hint: 'File name', confirmLabel: 'Create'))
        ?.trim();
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
        AppSnack.error(context, 'Create file failed: $e');
      }
    }
  }

  Future<void> _showRenameDialog(SftpPanelProvider prov, SftpEntry entry) async {
    final newName = (await showFileNameDialog(context,
            title: 'Rename', initial: entry.name, confirmLabel: 'Rename'))
        ?.trim();
    if (newName == null || newName.isEmpty || newName == entry.name || !mounted) return;
    final slash = entry.path.lastIndexOf('/');
    final parent = slash <= 0 ? '/' : entry.path.substring(0, slash);
    try {
      await context.read<SftpFileOpsService>().rename(widget.host!, entry.path, '$parent/$newName');
      prov.clearSelection();
      if (mounted) _loadDirectory(prov.currentPath);
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'Rename failed: $e');
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
    final result = await showYsDialog<({int mode, bool recursive})>(
      context,
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
        AppSnack.error(context, 'chmod ${modeToOctal(result.mode)} failed: $e');
      }
    }
  }

  Future<void> _showDeleteConfirm(SftpPanelProvider prov, List<SftpEntry> entries) async {
    final names = entries.map((e) => e.name).join(', ');
    final ok = await showYsDialog<bool>(
      context,
      builder: (ctx) => YsDialog(
        title: 'Delete',
        body: Text('Delete "$names"?\nThis cannot be undone.'),
        actions: [
          FButton(
            autofocus: true,
            variant: FButtonVariant.outline,
            onPress: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FButton(
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
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
        AppSnack.error(context, 'Delete failed: $e');
      }
    }
  }
}
