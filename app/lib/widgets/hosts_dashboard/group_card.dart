part of 'hosts_dashboard.dart';

// ── Group Card ────────────────────────────────────────────

class _GroupCard extends StatefulWidget {
  final String name;
  final int count;

  /// Set only for an empty pinned group; shows the hover "Delete group" menu.
  final VoidCallback? onDelete;
  const _GroupCard({required this.name, required this.count, this.onDelete});

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _hovered = false;

  /// A deletable group's card is a tab stop, so the keyboard can reveal its
  /// menu button (which is not focusable while hidden).
  final _focus = FocusNode(debugLabel: 'group-card');

  @override
  void initState() {
    super.initState();
    // Fires when focus enters/leaves the card or moves between the card and
    // its menu button (focus ring vs. button).
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// The menu lives in an overlay; keep its trigger visible while it is open
  /// (the pointer leaves the card to reach it).
  bool _menuOpen = false;

  void _setMenuOpen(bool open) {
    if (mounted && open != _menuOpen) setState(() => _menuOpen = open);
  }

  @override
  Widget build(BuildContext context) {
    final deletable = widget.onDelete != null;
    // The menu button stays mounted for a deletable group (so an open menu
    // survives the pointer leaving the card), but while hidden it can be
    // neither focused nor hit; hover or keyboard focus on the card shows it.
    final showMenu = _hovered || _focus.hasFocus || _menuOpen;
    final card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        focusNode: _focus,
        canRequestFocus: deletable,
        skipTraversal: !deletable,
        includeSemantics: deletable,
        child: SizedBox(
          width: 200,
          child: FCard(
            child: Padding(
              padding: const EdgeInsets.all(YsSpace.s3),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: YsColors.secondary,
                      borderRadius: BorderRadius.circular(YsRadius.control),
                    ),
                    child: const Icon(FLucideIcons.folder,
                        size: 16, color: YsColors.mutedForeground),
                  ),
                  const SizedBox(width: YsSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: YsColors.foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${widget.count} host${widget.count == 1 ? '' : 's'}',
                          style: const TextStyle(
                              color: YsColors.mutedForeground, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (deletable)
                    ExcludeFocus(
                      excluding: !showMenu,
                      child: IgnorePointer(
                        ignoring: !showMenu,
                        child: Opacity(
                            opacity: showMenu ? 1 : 0, child: _menu()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return FFocusedOutline(focused: _focus.hasPrimaryFocus, child: card);
  }

  Widget _menu() => FPopoverMenu(
        control: FPopoverControl.managed(onChange: _setMenuOpen),
        menuAnchor: Alignment.topRight,
        childAnchor: Alignment.bottomRight,
        menuBuilder: (context, controller, _) => [
          FItemGroup(
            children: [
              FItem(
                variant: .destructive,
                prefix: const Icon(FLucideIcons.trash2),
                title: const Text('Delete group'),
                onPress: () {
                  controller.hide();
                  widget.onDelete?.call();
                },
              ),
            ],
          ),
        ],
        builder: (context, controller, _) => Tooltip(
          message: 'Group options',
          child: FButton.icon(
            variant: .ghost,
            size: .xs,
            onPress: controller.toggle,
            child: const Icon(FLucideIcons.ellipsis),
          ),
        ),
      );
}
