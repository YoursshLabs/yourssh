// app/lib/widgets/entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_option.dart';

/// Right-click context menu for file/folder entries, shared by the remote
/// SFTP panel and the local file panel. Built on MenuAnchor so the
/// "Open with" entry cascades open on hover like a native menu.
///
/// Layout (│ = divider):
///   File:   Open · View · Edit · Open with ▸ │ Copy to target directory ·
///           Rename · Delete │ Refresh · New Folder · Edit Permissions │
///           Copy path
///   Folder: Open │ same as above
///
/// Optional callbacks hide their item when null, except Copy to target
/// directory which renders disabled with [copyToTargetDisabledReason].
class EntryContextMenu extends StatefulWidget {
  final String path;
  final bool isDirectory;
  final Widget child;

  /// Default action: folders navigate in, files open (editor / OS default).
  final VoidCallback onOpen;
  final VoidCallback? onView;
  final VoidCallback? onEdit;

  /// Fetches the installed-app list for this entry's file type. Called when
  /// the context menu opens; result is cached by AppDiscoveryService.
  final Future<List<AppOption>> Function()? loadApps;
  final void Function(AppOption app)? onOpenWithApp;
  final VoidCallback? onChooseApp;

  /// Copies the entry into the opposite panel's current directory. The item
  /// is disabled (with [copyToTargetDisabledReason] as a hint) when the
  /// transfer is not possible.
  final VoidCallback? onCopyToTarget;
  final String? copyToTargetDisabledReason;

  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  final VoidCallback onNewFolder;

  /// Null hides the item (e.g. local panel on Windows — no chmod).
  final VoidCallback? onEditPermissions;

  const EntryContextMenu({
    super.key,
    required this.path,
    required this.isDirectory,
    required this.child,
    required this.onOpen,
    this.onView,
    this.onEdit,
    this.loadApps,
    this.onOpenWithApp,
    this.onChooseApp,
    this.onCopyToTarget,
    this.copyToTargetDisabledReason,
    required this.onRename,
    required this.onDelete,
    required this.onRefresh,
    required this.onNewFolder,
    this.onEditPermissions,
  });

  @override
  State<EntryContextMenu> createState() => _EntryContextMenuState();
}

class _EntryContextMenuState extends State<EntryContextMenu> {
  final MenuController _controller = MenuController();
  List<AppOption>? _apps; // null = still loading

  static const _fg = Color(0xFFD4D4D4);
  static const _dim = Color(0xFF555555);

  ButtonStyle get _itemStyle => const ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(_fg),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
        padding:
            WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        minimumSize: WidgetStatePropertyAll(Size(160, 34)),
        maximumSize: WidgetStatePropertyAll(Size(320, 34)),
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

  MenuItemButton _item(String label, IconData icon, VoidCallback? onPressed,
      {Color? color}) {
    final c = color ?? _fg;
    return MenuItemButton(
      style: color == null
          ? _itemStyle
          : _itemStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(color)),
      leadingIcon: Icon(icon, size: 14, color: c),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  /// "Copy to target directory" — always listed; disabled with a reason
  /// hint when the transfer matrix cannot move this entry.
  Widget _copyToTargetItem() {
    final reason = widget.copyToTargetDisabledReason;
    final enabled = reason == null && widget.onCopyToTarget != null;
    return MenuItemButton(
      style: enabled
          ? _itemStyle
          : _itemStyle.copyWith(
              foregroundColor: const WidgetStatePropertyAll(_dim),
              maximumSize: const WidgetStatePropertyAll(Size(320, 48)),
            ),
      leadingIcon: Icon(Icons.drive_file_move_outline,
          size: 14, color: enabled ? _fg : _dim),
      onPressed: enabled ? widget.onCopyToTarget : null,
      child: reason == null
          ? const Text('Copy to target directory')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Copy to target directory'),
                Text(reason,
                    style: const TextStyle(fontSize: 10, color: _dim)),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDir = widget.isDirectory;
    return MenuAnchor(
      controller: _controller,
      style: _menuStyle,
      consumeOutsideTap: true,
      menuChildren: [
        _item('Open', isDir ? Icons.folder_open : Icons.open_in_new,
            widget.onOpen),
        if (!isDir && widget.onView != null)
          _item('View', Icons.visibility_outlined, widget.onView),
        if (!isDir && widget.onEdit != null)
          _item('Edit', Icons.edit_outlined, widget.onEdit),
        if (!isDir &&
            (widget.onOpenWithApp != null || widget.onChooseApp != null))
          SubmenuButton(
            style: _itemStyle,
            menuStyle: _menuStyle,
            leadingIcon: const Icon(Icons.apps, size: 14, color: _fg),
            menuChildren: _buildOpenWithChildren(),
            child: const Text('Open with'),
          ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        _copyToTargetItem(),
        _item('Rename', Icons.drive_file_rename_outline, widget.onRename),
        _item('Delete', Icons.delete_outline, widget.onDelete,
            color: const Color(0xFFEF4444)),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        _item('Refresh', Icons.refresh, widget.onRefresh),
        _item('New Folder', Icons.create_new_folder_outlined,
            widget.onNewFolder),
        if (widget.onEditPermissions != null)
          _item('Edit Permissions', Icons.lock_outline,
              widget.onEditPermissions),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        _item('Copy path', Icons.content_copy,
            () => Clipboard.setData(ClipboardData(text: widget.path))),
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
                      color:
                          const Color(0xFF22C55E).withValues(alpha: 0.15),
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
