import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/local_entry.dart';
import '../providers/local_file_panel_provider.dart';

class LocalFilePanel extends StatefulWidget {
  final LocalFilePanelProvider provider;

  const LocalFilePanel({super.key, required this.provider});

  @override
  State<LocalFilePanel> createState() => _LocalFilePanelState();
}

class _LocalFilePanelState extends State<LocalFilePanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.provider.reload();
    });
  }

  // ── Actions ─────────────────────────────────────────────

  Future<void> _createFolder() async {
    final name = await _showInputDialog(context, title: 'New Folder', hint: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    final newPath = p.join(widget.provider.currentPath, name.trim());
    try {
      await Directory(newPath).create();
      await widget.provider.reload();
    } catch (e) {
      if (mounted) _showError('Failed to create folder: $e');
    }
  }

  Future<void> _renameSelected() async {
    final selected = widget.provider.selectedEntries;
    if (selected.length != 1) return;
    final entry = selected.first;
    final newName = await _showInputDialog(context,
        title: 'Rename', hint: 'New name', initial: entry.name);
    if (newName == null || newName.trim().isEmpty || newName.trim() == entry.name) return;
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

  Future<void> _deleteSelected() async {
    final selected = widget.provider.selectedEntries.toList();
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete', style: TextStyle(color: Color(0xFFD4D4D4))),
        content: Text(
          'Delete ${selected.length} item(s)? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final entry in selected) {
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF2A1A1A)),
    );
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<LocalFilePanelProvider>(
        builder: (context, prov, _) => Column(
          children: [
            _buildHeader(prov),
            if (prov.filterVisible) _buildFilterBar(prov),
            _buildBreadcrumb(prov),
            _buildColumnHeader(),
            Expanded(child: _buildContent(prov)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalFilePanelProvider prov) {
    return Container(
      height: 40,
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.computer, size: 14, color: Color(0xFF888888)),
          const SizedBox(width: 6),
          const Text('Local',
              style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
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
              if (v == 'new_folder') _createFolder();
              if (v == 'rename') _renameSelected();
              if (v == 'delete') _deleteSelected();
            },
            itemBuilder: (_) => [
              _menuItem('new_folder', Icons.create_new_folder_outlined, 'New Folder'),
              _menuItem('rename', Icons.drive_file_rename_outline, 'Rename',
                  enabled: prov.selectedEntries.length == 1),
              _menuItem('delete', Icons.delete_outline, 'Delete',
                  enabled: prov.selectedEntries.isNotEmpty, isDestructive: true),
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

  Widget _buildFilterBar(LocalFilePanelProvider prov) {
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

  Widget _buildBreadcrumb(LocalFilePanelProvider prov) {
    final crumbs = _buildCrumbs(prov.currentPath);
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
            onPressed: prov.canGoBack ? prov.goBack : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                size: 16,
                color: prov.canGoForward
                    ? const Color(0xFF888888)
                    : const Color(0xFF333333)),
            onPressed: prov.canGoForward ? prov.goForward : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < crumbs.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right,
                            size: 13, color: Color(0xFF444444)),
                      ),
                    GestureDetector(
                      onTap: () => prov.loadDirectory(crumbs[i].path),
                      child: Text(
                        crumbs[i].label,
                        style: TextStyle(
                          color: i == crumbs.length - 1
                              ? const Color(0xFFD4D4D4)
                              : const Color(0xFF666666),
                          fontSize: 12,
                          fontWeight: i == crumbs.length - 1
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 13, color: Color(0xFF555555)),
            onPressed: prov.reload,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeader() {
    return Container(
      height: 26,
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: const Row(
        children: [
          Expanded(
            flex: 5,
            child: Text('Name',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
          Expanded(
            flex: 3,
            child: Text('Date Modified',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
          SizedBox(
            width: 70,
            child: Text('Size',
                style: TextStyle(
                    color: Color(0xFF555555), fontSize: 11),
                textAlign: TextAlign.right),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text('Kind',
                style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(LocalFilePanelProvider prov) {
    if (prov.loadState == LocalFilePanelLoadState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (prov.loadState == LocalFilePanelLoadState.error) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 28),
          const SizedBox(height: 8),
          Text(prov.errorMessage ?? 'Error',
              style:
                  const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: prov.reload,
            icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF888888)),
            label: const Text('Retry',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
          ),
        ]),
      );
    }
    final entries = prov.filteredEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          prov.filterQuery.isNotEmpty ? 'No matches' : 'Empty directory',
          style: const TextStyle(color: Color(0xFF444444), fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) => _buildEntryRow(entries[i], prov),
    );
  }

  Widget _buildEntryRow(LocalEntry entry, LocalFilePanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return Draggable<LocalEntry>(
      data: entry,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(entry.name,
              style: const TextStyle(
                  color: Color(0xFF22C55E), fontSize: 13)),
        ),
      ),
      child: GestureDetector(
        onTap: () {
          final isMulti = HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed;
          if (isMulti) {
            prov.toggleSelection(entry);
          } else {
            prov.selectOnly(entry);
          }
        },
        onDoubleTap: () {
          if (entry.isDirectory) prov.loadDirectory(entry.path);
        },
        onSecondaryTapUp: (d) {
          prov.selectOnly(entry);
          _showContextMenu(entry, prov, d.globalPosition);
        },
        child: Container(
          color: isSelected
              ? const Color(0xFF22C55E).withValues(alpha: 0.08)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Icon(
                      entry.isDirectory
                          ? Icons.folder
                          : _fileIcon(entry.extension),
                      size: 15,
                      color: entry.isDirectory
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF60A5FA),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.name,
                              style: const TextStyle(
                                  color: Color(0xFFD4D4D4), fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                          Text(entry.permissions,
                              style: const TextStyle(
                                  color: Color(0xFF444444),
                                  fontSize: 10,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  _formatDate(entry.modifiedAt),
                  style: const TextStyle(
                      color: Color(0xFF666666), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  entry.formattedSize,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: Text(
                  entry.kindLabel,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(LocalEntry entry, LocalFilePanelProvider prov, Offset pos) {
    final size = MediaQuery.of(context).size;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, size.width - pos.dx, size.height - pos.dy),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF2A2A2A))),
      items: [
        PopupMenuItem(
          onTap: _renameSelected,
          child: _contextItem(Icons.drive_file_rename_outline, 'Rename'),
        ),
        PopupMenuItem(
          onTap: _deleteSelected,
          child: _contextItem(Icons.delete_outline, 'Delete',
              color: Colors.red),
        ),
      ],
    );
  }

  Widget _contextItem(IconData icon, String label,
      {Color color = const Color(0xFFD4D4D4)}) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: color)),
    ]);
  }

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'go' || 'rs' || 'c' || 'cpp' =>
        Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}/${dt.year}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<({String label, String path})> _buildCrumbs(String path) {
    if (Platform.isWindows) {
      final parts =
          path.split('\\').where((s) => s.isNotEmpty).toList();
      return [
        for (int i = 0; i < parts.length; i++)
          (
            label: parts[i],
            path: parts.sublist(0, i + 1).join('\\') +
                (i == 0 ? '\\' : ''),
          )
      ];
    }
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return [
      (label: 'Macintosh HD', path: '/'),
      for (int i = 0; i < parts.length; i++)
        (
          label: parts[i],
          path: '/${parts.sublist(0, i + 1).join('/')}',
        ),
    ];
  }

  static Future<String?> _showInputDialog(BuildContext context,
      {required String title,
      required String hint,
      String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title,
            style: const TextStyle(
                color: Color(0xFFD4D4D4), fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
              color: Color(0xFFD4D4D4), fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: Color(0xFF555555), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF111111),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF2A2A2A))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF2A2A2A))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF22C55E))),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK',
                style: TextStyle(color: Color(0xFF22C55E))),
          ),
        ],
      ),
    );
  }
}

// ── _HeaderButton ────────────────────────────────────────────

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
