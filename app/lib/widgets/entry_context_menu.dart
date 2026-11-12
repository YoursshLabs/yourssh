// app/lib/widgets/entry_context_menu.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/app_option.dart';

/// Right-click context menu for file/folder entries, shared by the remote
/// SFTP panel and the local file panel. A forui [FPopoverMenu] opened at the
/// pointer; "Open with" is an [FSubmenuItem] that cascades open on hover
/// like a native menu.
///
/// Layout (│ = group divider):
///   File:   Open · View · Edit · Open with ▸ │ Copy to target directory ·
///           Rename · Delete │ Refresh · New Folder · Edit Permissions │
///           Copy path
///   Folder: Open │ same as above
///
/// Optional callbacks hide their item when null, except Copy to target
/// directory which renders disabled with [copyToTargetDisabledReason].
///
/// Used two ways: as a wrapper, a right-click on [child] opens the menu; or
/// as a description handed to [show], which opens it at a global position
/// (the file table reports right-clicks with `onContextMenu(row, position)`
/// instead of wrapping every row).
class EntryContextMenu extends StatelessWidget {
  final String path;
  final bool isDirectory;

  /// The right-click target. Null when the menu is opened with [show].
  final Widget? child;

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
    this.child,
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

  /// The menu currently open (any panel); a new one replaces it.
  static OverlayEntry? _open;

  /// The context [show] was called with for [_open].
  static BuildContext? _openOwner;

  /// Closes the open menu if [owner] opened it — panels call this from
  /// `dispose` so a menu never outlives the panel whose actions it runs.
  static void dismissOwnedBy(BuildContext owner) {
    if (!identical(_openOwner, owner)) return;
    final entry = _open;
    _open = null;
    _openOwner = null;
    if (entry == null) return;
    // Still inserted (cleared from [_open] whenever it is removed); also
    // fine when its overlay is already gone.
    entry
      ..remove()
      ..dispose();
  }

  /// Opens this menu with its top-left corner at [globalPosition] (flipped
  /// to stay on screen) in the nearest overlay of [context].
  void show(BuildContext context, Offset globalPosition) {
    if (_openOwner case final owner?) dismissOwnedBy(owner);
    final overlay = Overlay.of(context);
    final box = overlay.context.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(globalPosition) ?? globalPosition;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _EntryMenuOverlay(
        menu: this,
        owner: context,
        position: local,
        onClosed: () {
          if (!identical(_open, entry)) return; // already dismissed
          _open = null;
          _openOwner = null;
          entry
            ..remove()
            ..dispose();
        },
      ),
    );
    _open = entry;
    _openOwner = context;
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onSecondaryTapUp: (d) => show(context, d.globalPosition),
        child: child,
      );
}

class _EntryMenuOverlay extends StatefulWidget {
  const _EntryMenuOverlay({
    required this.menu,
    required this.owner,
    required this.position,
    required this.onClosed,
  });

  final EntryContextMenu menu;

  /// Where the menu was opened from; actions only run while it is mounted.
  final BuildContext owner;
  final Offset position;
  final VoidCallback onClosed;

  @override
  State<_EntryMenuOverlay> createState() => _EntryMenuOverlayState();
}

class _EntryMenuOverlayState extends State<_EntryMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  final FocusScopeNode _scope = FocusScopeNode(
      debugLabel: 'EntryContextMenu',
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  /// Focus when the menu opened (the file list), restored on Escape or an
  /// outside tap.
  FocusNode? _previousFocus;
  List<AppOption>? _apps; // null = still loading
  bool _closed = false;

  EntryContextMenu get _menu => widget.menu;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleChange);
    _loadApps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Read now, not in show(): a right-click focuses the list first.
      _previousFocus = FocusManager.instance.primaryFocus;
      unawaited(_controller.show());
      // The menu takes the keyboard (arrows, Enter, Escape) even when the
      // list already holds focus, which FocusScope.autofocus would skip.
      // Its scope is attached once the portal has been built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closed) _scope.requestFocus();
      });
    });
  }

  void _loadApps() {
    final load = _menu.loadApps;
    if (load == null || _menu.isDirectory) return;
    try {
      load().then((apps) {
        if (mounted) setState(() => _apps = apps);
      }, onError: (_) {
        if (mounted) setState(() => _apps = const []);
      });
    } catch (_) {
      _apps = const [];
    }
  }

  void _handleChange() {
    if (!_closed && _controller.status.isDismissed) {
      _closed = true;
      // Escape / outside tap leave the focus in the closing menu: give the
      // keyboard back to the list. An action that opened a dialog owns the
      // focus by now and keeps it.
      final focus = FocusManager.instance.primaryFocus;
      final previous = _previousFocus;
      final stranded = _scope.hasFocus ||
          focus == null ||
          focus == FocusManager.instance.rootScope;
      if (stranded && previous != null && previous.context != null) {
        previous.requestFocus();
      }
      widget.onClosed();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChange)
      ..dispose();
    _scope.dispose();
    super.dispose();
  }

  /// Closes the menu, then runs [action] if its panel is still there.
  VoidCallback _run(VoidCallback action) => () {
        unawaited(_controller.hide());
        if (widget.owner.mounted) action();
      };

  FItem _item(
    String label,
    IconData icon,
    VoidCallback action, {
    bool destructive = false,
  }) =>
      FItem(
        variant: destructive ? FItemVariant.destructive : FItemVariant.primary,
        prefix: Icon(icon),
        title: Text(label),
        onPress: _run(action),
      );

  /// "Copy to target directory" — always listed; disabled with a reason
  /// hint when the transfer matrix cannot move this entry.
  FItem _copyToTargetItem() {
    final reason = _menu.copyToTargetDisabledReason;
    final onCopy = _menu.onCopyToTarget;
    final enabled = reason == null && onCopy != null;
    return FItem(
      enabled: enabled,
      prefix: const Icon(FLucideIcons.folderInput),
      title: const Text('Copy to target directory'),
      subtitle: reason == null ? null : Text(reason),
      onPress: enabled ? _run(onCopy) : null,
    );
  }

  List<FItemGroupMixin> _openWithMenu() {
    final apps = _apps;
    return [
      if (apps == null)
        FItemGroup(children: [
          FItem(enabled: false, title: const Text('Searching apps…')),
        ])
      else if (apps.isNotEmpty)
        FItemGroup(children: [
          for (final app in apps)
            FItem(
              title: Text(app.name),
              suffix: app.isDefault ? const YsStatusBadge('default') : null,
              onPress: _run(() => _menu.onOpenWithApp?.call(app)),
            ),
        ]),
      FItemGroup(children: [
        FItem(
          prefix: const Icon(FLucideIcons.folderOpen),
          title: const Text('Choose…'),
          onPress: _menu.onChooseApp == null ? null : _run(_menu.onChooseApp!),
        ),
      ]),
    ];
  }

  List<FItemGroupMixin> _groups() {
    final m = _menu;
    final isDir = m.isDirectory;
    return [
      FItemGroup(children: [
        _item('Open', isDir ? FLucideIcons.folderOpen : FLucideIcons.externalLink,
            m.onOpen),
        if (!isDir && m.onView != null)
          _item('View', FLucideIcons.eye, m.onView!),
        if (!isDir && m.onEdit != null)
          _item('Edit', FLucideIcons.squarePen, m.onEdit!),
        if (!isDir && (m.onOpenWithApp != null || m.onChooseApp != null))
          FSubmenuItem(
            prefix: const Icon(FLucideIcons.appWindow),
            title: const Text('Open with'),
            submenu: _openWithMenu(),
          ),
      ]),
      FItemGroup(children: [
        _copyToTargetItem(),
        _item('Rename', FLucideIcons.pencilLine, m.onRename),
        _item('Delete', FLucideIcons.trash2, m.onDelete, destructive: true),
      ]),
      FItemGroup(children: [
        _item('Refresh', FLucideIcons.refreshCw, m.onRefresh),
        _item('New Folder', FLucideIcons.folderPlus, m.onNewFolder),
        if (m.onEditPermissions != null)
          _item('Edit Permissions', FLucideIcons.lock, m.onEditPermissions!),
      ]),
      FItemGroup(children: [
        _item('Copy path', FLucideIcons.copy,
            () => Clipboard.setData(ClipboardData(text: m.path))),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Like the old MenuAnchor's consumeOutsideTap: a click outside only
        // closes the menu and never reaches the list below (where a click
        // opens a remote folder or file).
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => unawaited(_controller.hide()),
          ),
        ),
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy,
          child: FPopoverMenu(
            control: FPopoverControl.managed(controller: _controller),
            menuAnchor: Alignment.topLeft,
            childAnchor: Alignment.topLeft,
            spacing: FPortalSpacing.zero,
            focusNode: _scope,
            menuBuilder: (context, controller, _) => _groups(),
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
