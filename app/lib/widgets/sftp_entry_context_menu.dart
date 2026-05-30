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
