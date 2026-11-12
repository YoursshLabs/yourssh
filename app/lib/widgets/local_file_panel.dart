import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/local_entry.dart';
import '../providers/local_file_panel_provider.dart';
import '../services/app_discovery_service.dart';
import '../util/app_launcher.dart';
import '../util/entry_sort.dart';
import '../util/file_mode.dart';
import '../util/fs_error.dart';
import 'entry_context_menu.dart';
import 'file_panel_chrome.dart';
import 'path_breadcrumb.dart';
import 'permissions_dialog.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class LocalFilePanel extends StatefulWidget {
  final LocalFilePanelProvider provider;

  /// When set, shows a "Local" source chip next to the breadcrumb that
  /// opens the panel's source picker (two-panel SFTP layout).
  final VoidCallback? onChangeSource;

  /// Copies [entry] into the opposite panel's current directory (wired by
  /// the dual-panel screen). Null when the panel is used standalone.
  final void Function(LocalEntry entry)? onCopyToTarget;

  /// Why copy-to-target is unavailable for [entry] (null = available).
  final String? Function(LocalEntry entry)? copyToTargetBlockReason;

  const LocalFilePanel({
    super.key,
    required this.provider,
    this.onChangeSource,
    this.onCopyToTarget,
    this.copyToTargetBlockReason,
  });

  @override
  State<LocalFilePanel> createState() => _LocalFilePanelState();
}

class _LocalFilePanelState extends State<LocalFilePanel>
    with MidnightRefresh {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.provider.reload();
    });
  }

  @override
  void dispose() {
    EntryContextMenu.dismissOwnedBy(context);
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────

  Future<void> _createFolder() async {
    final name = await showFileNameDialog(
      context,
      title: 'New Folder',
      hint: 'Folder name',
      confirmLabel: 'OK',
    );
    if (name == null || name.trim().isEmpty) return;
    final newPath = p.join(widget.provider.currentPath, name.trim());
    try {
      await Directory(newPath).create();
      if (mounted) await widget.provider.reload();
    } catch (e) {
      if (mounted) {
        _showError('Failed to create folder: '
            '${describeFileSystemError(e, path: newPath)}');
      }
    }
  }

  Future<void> _renameSelected() async {
    final selected = widget.provider.selectedEntries;
    if (selected.length != 1) return;
    await _rename(selected.first);
  }

  Future<void> _rename(LocalEntry entry) async {
    final newName = await showFileNameDialog(
      context,
      title: 'Rename',
      hint: 'New name',
      initial: entry.name,
      confirmLabel: 'OK',
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
      if (mounted) await widget.provider.reload();
    } catch (e) {
      if (mounted) {
        _showError(
            'Rename failed: ${describeFileSystemError(e, path: entry.path)}');
      }
    }
  }

  Future<void> _deleteSelected() =>
      _delete(widget.provider.selectedEntries.toList());

  Future<void> _delete(List<LocalEntry> entries) async {
    if (entries.isEmpty) return;
    final confirmed = await showYsDialog<bool>(
      context,
      builder: (ctx) => YsDialog(
        title: 'Delete',
        body: Text('Delete ${entries.length} item(s)? This cannot be undone.'),
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
    if (confirmed != true) return;
    try {
      for (final entry in entries) {
        if (entry.isDirectory) {
          await Directory(entry.path).delete(recursive: true);
        } else {
          await File(entry.path).delete();
        }
      }
      if (mounted) await widget.provider.reload();
    } catch (e) {
      if (mounted) {
        _showError('Delete failed: '
            '${describeFileSystemError(e, path: entries.first.path)}');
      }
    }
  }

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
    final result = await showYsDialog<({int mode, bool recursive})>(
      context,
      builder: (_) => PermissionsDialog(
        entryName: entry.name,
        // Scan-time mode from the model — no blocking statSync at
        // dialog-open; null (stat failed) makes the dialog gate Apply.
        initialMode: entry.mode,
        isDirectory: entry.isDirectory,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await chmodLocal(entry.path, result.mode, recursive: result.recursive);
      if (mounted) await widget.provider.reload();
    } catch (e) {
      if (mounted) {
        _showError(
            'chmod failed: ${describeFileSystemError(e, path: entry.path)}');
      }
    }
  }

  void _showError(String message) {
    AppSnack.error(context, message);
  }

  // ── Build ────────────────────────────────────────────────

  /// Columns of the file table. Kept for the day so unchanged rows are
  /// reused across selection changes; cells depend only on the entry (and
  /// the date, through the "Today" labels).
  List<YsColumn<LocalEntry>> get _columns => dayColumns(() => [
    YsColumn<LocalEntry>(
      id: EntrySortColumn.name,
      label: 'Name',
      flex: 5,
      sortable: true,
      cell: (_, e) => FileNameCell(
          name: e.name, isDirectory: e.isDirectory, extension: e.extension),
    ),
    YsColumn<LocalEntry>(
      id: EntrySortColumn.modified,
      label: 'Modified',
      width: 120,
      sortable: true,
      minTableWidth: 400,
      cell: (_, e) => FileMetaCell(formatEntryDate(e.modifiedAt)),
    ),
    YsColumn<LocalEntry>(
      id: EntrySortColumn.size,
      label: 'Size',
      width: 70,
      sortable: true,
      numeric: true,
      cell: (_, e) => FileMetaCell(e.formattedSize),
    ),
    YsColumn<LocalEntry>(
      id: EntrySortColumn.kind,
      label: 'Kind',
      width: 70,
      sortable: true,
      minTableWidth: 580,
      cell: (_, e) => FileMetaCell(e.kindLabel),
    ),
    YsColumn<LocalEntry>(
      id: 'permissions',
      label: 'Permissions',
      width: 90,
      minTableWidth: 500,
      cell: (_, e) => FileMetaCell(e.permissions, mono: true),
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<LocalFilePanelProvider>(
        builder: (context, prov, _) {
          final selected = prov.selectedEntries;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(prov, selected),
              if (prov.filterVisible)
                FilePanelFilterBar(onChanged: prov.setFilterQuery),
              _buildPathBar(prov),
              Expanded(child: _buildContent(prov, selected)),
              if (prov.loadState == LocalFilePanelLoadState.loaded &&
                  prov.filteredEntries.isNotEmpty)
                FilePanelFooter(selected.isEmpty
                    ? '${prov.filteredEntries.length} items'
                    : '${selected.length} selected'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(LocalFilePanelProvider prov, Set<LocalEntry> selected) {
    return FilePanelHeader(
      // Clickable source chip (two-panel layout): switch this slot between
      // Local and any saved host. Standalone, "Local" is a plain label.
      sourceIcon: widget.onChangeSource == null
          ? FLucideIcons.monitor
          : FLucideIcons.laptop,
      sourceLabel: 'Local',
      onChangeSource: widget.onChangeSource,
      filterActive: prov.filterVisible,
      onToggleFilter: prov.toggleFilterVisible,
      actions: [
        FilePanelAction(
            'New Folder', FLucideIcons.folderPlus, _createFolder),
        FilePanelAction('Rename', FLucideIcons.pencilLine, _renameSelected,
            enabled: selected.length == 1),
        FilePanelAction('Delete', FLucideIcons.trash2, _deleteSelected,
            enabled: selected.isNotEmpty, destructive: true),
      ],
    );
  }

  Widget _buildPathBar(LocalFilePanelProvider prov) {
    return FilePanelPathBar(
      canGoBack: prov.canGoBack,
      canGoForward: prov.canGoForward,
      onBack: prov.goBack,
      onForward: prov.goForward,
      onRefresh: prov.reload,
      breadcrumb: PathBreadcrumb(
        crumbs: _buildCrumbs(prov.currentPath),
        onNavigate: prov.loadDirectory,
        editablePath: prov.currentPath,
      ),
    );
  }

  Widget _buildContent(LocalFilePanelProvider prov, Set<LocalEntry> selected) {
    // The table stays mounted through loading / error / empty listings so
    // it keeps keyboard focus across a folder change.
    final loaded = prov.loadState != LocalFilePanelLoadState.loading &&
        prov.loadState != LocalFilePanelLoadState.error;
    final entries = loaded ? prov.filteredEntries : const <LocalEntry>[];
    return YsFileTable<LocalEntry>(
      rows: entries,
      columns: _columns,
      selected: selected,
      sort: YsSort(prov.sortColumn, ascending: prov.sortAscending),
      onSort: (s) => prov.setSort(s.column, ascending: s.ascending),
      onSelect: prov.select,
      onSelectAll: (all) => all ? prov.selectAll() : prov.deselectAll(),
      // Double-click / Enter: the menu's Open (folders navigate in, files
      // open in the default application).
      onOpen: _openEntry,
      onContextMenu: (entry, position) =>
          _entryMenu(entry).show(context, position),
      rowKey: (e) => e.path,
      emptyState: switch (prov.loadState) {
        LocalFilePanelLoadState.loading =>
          const Center(child: FCircularProgress()),
        LocalFilePanelLoadState.error =>
          FilePanelError(prov.errorMessage ?? 'Error', onRetry: prov.reload),
        _ => FilePanelMessage(
            prov.filterQuery.isNotEmpty ? 'No matches' : 'Empty directory'),
      },
      checkboxes: true,
      selectAllKey: const Key('local_select_all'),
      draggable: true,
      rowLabel: (e) => e.name,
    );
  }

  /// The shared entry context menu for [entry].
  EntryContextMenu _entryMenu(LocalEntry entry) {
    return EntryContextMenu(
      path: entry.path,
      isDirectory: entry.isDirectory,
      onOpen: () => _openEntry(entry),
      loadApps: entry.isDirectory
          ? null
          : () => context.read<AppDiscoveryService>().getAppsFor(entry.path),
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
      onEditPermissions:
          Platform.isWindows ? null : () => _showPermissionsDialog(entry),
    );
  }

  List<({String label, String path})> _buildCrumbs(String path) {
    if (Platform.isWindows) {
      final parts = path.split('\\').where((s) => s.isNotEmpty).toList();
      return [
        for (int i = 0; i < parts.length; i++)
          (
            label: parts[i],
            path: parts.sublist(0, i + 1).join('\\') + (i == 0 ? '\\' : ''),
          ),
      ];
    }
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return [
      (label: 'Macintosh HD', path: '/'),
      for (int i = 0; i < parts.length; i++)
        (label: parts[i], path: '/${parts.sublist(0, i + 1).join('/')}'),
    ];
  }
}
