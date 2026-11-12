part of 'hosts_dashboard.dart';

// ── Top Bar ───────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback? onAddHost;
  final VoidCallback? onLocalTerminal;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  final VoidCallback? onDiscover;
  final VoidCallback? onSelect;
  final HostSortMode sortMode;
  final ValueChanged<HostSortMode> onSortChanged;
  final String viewMode;
  final ValueChanged<String> onViewChanged;

  const _TopBar({
    required this.controller,
    required this.onSearch,
    this.onAddHost,
    this.onLocalTerminal,
    this.onNewGroup,
    this.onImport,
    this.onDiscover,
    this.onSelect,
    required this.sortMode,
    required this.onSortChanged,
    required this.viewMode,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          YsSpace.s5, YsSpace.s4, YsSpace.s5, YsSpace.s2),
      child: LayoutBuilder(builder: (context, constraints) {
        // The action cluster keeps its natural width and the search field
        // absorbs the rest; once the window narrows past a minimum search
        // width (e.g. host panel open) the cluster scrolls instead of
        // overflowing — same pattern as BulkActionBar.
        const minSearchWidth = 180.0;
        final clusterMax = (constraints.maxWidth - minSearchWidth - YsSpace.s3)
            .clamp(0.0, double.infinity);
        // Below this width Discover / Select / Local terminal drop their
        // labels (the tooltip keeps them) so New host stays in view at the
        // 900 px window minimum.
        final compact = constraints.maxWidth < 900;
        return Row(
          children: [
            Expanded(
              child: FTextField(
                key: const Key('hosts-search'),
                control: FTextFieldControl.managed(
                  controller: controller,
                  onChange: (v) => onSearch(v.text),
                ),
                size: .sm,
                hint: 'Search hosts, IPs, or tags...',
                prefixBuilder: (context, style, variants) =>
                    FTextField.prefixIconBuilder(context, style, variants,
                        const Icon(FLucideIcons.search)),
              ),
            ),
            const SizedBox(width: YsSpace.s3),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: clusterMax),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SortBtn(mode: sortMode, onChanged: onSortChanged),
                    const SizedBox(width: YsSpace.s2),
                    _ViewToggle(viewMode: viewMode, onChanged: onViewChanged),
                    const SizedBox(width: YsSpace.s2),
                    _ToolbarBtn(
                      key: const Key('hosts-discover'),
                      icon: FLucideIcons.radar,
                      label: 'Discover',
                      compact: compact,
                      onPress: onDiscover ?? () {},
                    ),
                    const SizedBox(width: YsSpace.s2),
                    _ToolbarBtn(
                      key: const Key('hosts-select'),
                      icon: FLucideIcons.squareCheck,
                      label: 'Select',
                      compact: compact,
                      onPress: onSelect ?? () {},
                    ),
                    const SizedBox(width: YsSpace.s2),
                    _ToolbarBtn(
                      key: const Key('hosts-local-terminal'),
                      icon: FLucideIcons.squareTerminal,
                      label: 'Local terminal',
                      compact: compact,
                      onPress: onLocalTerminal ?? () {},
                    ),
                    const SizedBox(width: YsSpace.s2),
                    _SplitNewBtn(
                      onNewHost: onAddHost ?? () {},
                      onNewGroup: onNewGroup,
                      onImport: onImport,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Outline toolbar button; icon-only with a tooltip when [compact].
class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onPress;
  const _ToolbarBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onPress,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => compact
      ? Tooltip(
          message: label,
          // The button's semanticsLabel is the one accessible name; the
          // tooltip would announce it a second time on a parent node.
          excludeFromSemantics: true,
          child: FButton.icon(
            variant: .outline,
            size: .sm,
            semanticsLabel: label,
            onPress: onPress,
            child: Icon(icon),
          ),
        )
      : FButton(
          variant: .outline,
          size: .sm,
          mainAxisSize: MainAxisSize.min,
          onPress: onPress,
          prefix: Icon(icon),
          child: Text(label),
        );
}

/// Dropdown button showing the current sort mode; opens a menu with all
/// HostSortMode values.
class _SortBtn extends StatelessWidget {
  final HostSortMode mode;
  final ValueChanged<HostSortMode> onChanged;
  const _SortBtn({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FPopoverMenu(
      menuAnchor: Alignment.topLeft,
      childAnchor: Alignment.bottomLeft,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (final m in HostSortMode.values)
              FItem(
                prefix: Icon(
                  FLucideIcons.check,
                  color: m == mode ? YsColors.primary : Colors.transparent,
                ),
                title: Text(m.label),
                selected: m == mode,
                onPress: () {
                  controller.hide();
                  onChanged(m);
                },
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton(
        variant: .outline,
        size: .sm,
        mainAxisSize: MainAxisSize.min,
        onPress: controller.toggle,
        prefix: const Icon(FLucideIcons.arrowDownUp),
        suffix: const Icon(FLucideIcons.chevronDown),
        child: Text(mode.label),
      ),
    );
  }
}

/// Segmented grid/list switch for the hosts dashboard.
class _ViewToggle extends StatelessWidget {
  final String viewMode; // 'grid' | 'list'
  final ValueChanged<String> onChanged;
  const _ViewToggle({required this.viewMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _segment(FLucideIcons.layoutGrid, 'Grid view', 'grid'),
        const SizedBox(width: 2),
        _segment(FLucideIcons.list, 'List view', 'list'),
      ],
    );
  }

  Widget _segment(IconData icon, String tooltip, String mode) {
    final active = viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: FButton.icon(
        variant: active ? .secondary : .ghost,
        size: .sm,
        selected: active,
        onPress: () => onChanged(mode),
        child: Icon(
          icon,
          color: active ? YsColors.foreground : YsColors.mutedForeground,
        ),
      ),
    );
  }
}

/// "New host" primary button with an attached menu (New Group / Import).
class _SplitNewBtn extends StatelessWidget {
  final VoidCallback onNewHost;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  const _SplitNewBtn({
    required this.onNewHost,
    this.onNewGroup,
    this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FButton(
          size: .sm,
          mainAxisSize: MainAxisSize.min,
          onPress: onNewHost,
          prefix: const Icon(FLucideIcons.plus),
          child: const Text('New host'),
        ),
        const SizedBox(width: 1),
        FPopoverMenu(
          menuAnchor: Alignment.topRight,
          childAnchor: Alignment.bottomRight,
          menuBuilder: (context, controller, _) => [
            FItemGroup(
              children: [
                FItem(
                  prefix: const Icon(FLucideIcons.folderPlus),
                  title: const Text('New group'),
                  onPress: () {
                    controller.hide();
                    onNewGroup?.call();
                  },
                ),
                FItem(
                  prefix: const Icon(FLucideIcons.fileUp),
                  title: const Text('Import'),
                  onPress: () {
                    controller.hide();
                    onImport?.call();
                  },
                ),
              ],
            ),
          ],
          builder: (context, controller, _) => Tooltip(
            message: 'Show menu',
            child: FButton.icon(
              variant: .primary,
              size: .sm,
              onPress: controller.toggle,
              child: const Icon(FLucideIcons.chevronDown),
            ),
          ),
        ),
      ],
    );
  }
}
