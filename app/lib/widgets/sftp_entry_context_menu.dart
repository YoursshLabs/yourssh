// app/lib/widgets/sftp_entry_context_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_option.dart';
import '../models/sftp_entry.dart';

/// Right-click context menu for SFTP entries, built on MenuAnchor so the
/// "Open with" entry cascades open on hover like a native menu.
class SftpEntryContextMenu extends StatefulWidget {
  final SftpEntry entry;
  final Widget child;
  // Directories use onOpen (Enter); files use the split callbacks below.
  final VoidCallback onOpen;
  final VoidCallback? onView;
  final VoidCallback? onEdit;

  /// Fetches the installed-app list for this entry's file type. Called when
  /// the context menu opens; result is cached by AppDiscoveryService.
  final Future<List<AppOption>> Function()? loadApps;
  final void Function(AppOption app)? onOpenWithApp;
  final VoidCallback? onChooseApp;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const SftpEntryContextMenu({
    super.key,
    required this.entry,
    required this.child,
    required this.onOpen,
    this.onView,
    this.onEdit,
    this.loadApps,
    this.onOpenWithApp,
    this.onChooseApp,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<SftpEntryContextMenu> createState() => _SftpEntryContextMenuState();
}

class _SftpEntryContextMenuState extends State<SftpEntryContextMenu> {
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

  @override
  Widget build(BuildContext context) {
    final isDir = widget.entry.isDirectory;
    return MenuAnchor(
      controller: _controller,
      style: _menuStyle,
      consumeOutsideTap: true,
      menuChildren: [
        MenuItemButton(
          style: _itemStyle,
          leadingIcon: Icon(
              isDir ? Icons.folder_open : Icons.visibility_outlined,
              size: 14,
              color: _fg),
          onPressed: isDir ? widget.onOpen : widget.onView,
          child: Text(isDir ? 'Enter' : 'View'),
        ),
        if (!isDir && widget.onEdit != null)
          MenuItemButton(
            style: _itemStyle,
            leadingIcon:
                const Icon(Icons.edit_outlined, size: 14, color: _fg),
            onPressed: widget.onEdit,
            child: const Text('Edit'),
          ),
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
        MenuItemButton(
          style: _itemStyle,
          leadingIcon: const Icon(Icons.drive_file_rename_outline,
              size: 14, color: _fg),
          onPressed: widget.onRename,
          child: const Text('Rename'),
        ),
        MenuItemButton(
          style: _itemStyle.copyWith(
              foregroundColor:
                  const WidgetStatePropertyAll(Color(0xFFEF4444))),
          leadingIcon: const Icon(Icons.delete_outline,
              size: 14, color: Color(0xFFEF4444)),
          onPressed: widget.onDelete,
          child: const Text('Delete'),
        ),
        const Divider(height: 1, color: Color(0xFF2A2A2A)),
        MenuItemButton(
          style: _itemStyle,
          leadingIcon: const Icon(Icons.content_copy, size: 14, color: _fg),
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: widget.entry.path)),
          child: const Text('Copy path'),
        ),
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
