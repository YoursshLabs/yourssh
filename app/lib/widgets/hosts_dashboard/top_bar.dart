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
        // Controls drop out by priority as the bar narrows, so nothing is
        // ever clipped (the search field absorbs whatever is left):
        //   >= 900  labelled buttons, labelled sort
        //   >= 760  icon-only Discover / Select / Local terminal
        //   >= 560  ... and an icon-only sort
        //   <  560  sort, view, Discover, Select and Local terminal move into
        //           one "More" menu
        // New host stays visible always; below 440 it is icon-only too.
        final w = constraints.maxWidth;
        final labels = w >= 900;
        final sortLabel = w >= 760;
        final inline = w >= 560;
        final newLabel = w >= 440;
        return Row(
          key: const Key('hosts-toolbar'),
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
            if (inline) ...[
              _SortBtn(
                key: const Key('hosts-sort'),
                mode: sortMode,
                onChanged: onSortChanged,
                compact: !sortLabel,
              ),
              const SizedBox(width: YsSpace.s2),
              _ViewToggle(
                key: const Key('hosts-view-toggle'),
                viewMode: viewMode,
                onChanged: onViewChanged,
              ),
              const SizedBox(width: YsSpace.s2),
              _ToolbarBtn(
                key: const Key('hosts-discover'),
                icon: FLucideIcons.radar,
                label: 'Discover',
                compact: !labels,
                onPress: onDiscover ?? () {},
              ),
              const SizedBox(width: YsSpace.s2),
              _ToolbarBtn(
                key: const Key('hosts-select'),
                icon: FLucideIcons.squareCheck,
                label: 'Select',
                compact: !labels,
                onPress: onSelect ?? () {},
              ),
              const SizedBox(width: YsSpace.s2),
              _ToolbarBtn(
                key: const Key('hosts-local-terminal'),
                icon: FLucideIcons.squareTerminal,
                label: 'Local terminal',
                compact: !labels,
                onPress: onLocalTerminal ?? () {},
              ),
            ] else ...[
              _MoreMenu(
                key: const Key('hosts-more'),
                sortMode: sortMode,
                onSortChanged: onSortChanged,
                viewMode: viewMode,
                onViewChanged: onViewChanged,
                onDiscover: onDiscover,
                onSelect: onSelect,
                onLocalTerminal: onLocalTerminal,
              ),
            ],
            const SizedBox(width: YsSpace.s2),
            _SplitNewBtn(
              key: const Key('hosts-new-split'),
              compact: !newLabel,
              onNewHost: onAddHost ?? () {},
              onNewGroup: onNewGroup,
              onImport: onImport,
            ),
          ],
        );
      }),
    );
  }
}

/// Everything that does not fit inline on a narrow bar: the secondary actions,
/// the grid/list switch and the sort modes.
class _MoreMenu extends StatelessWidget {
  final HostSortMode sortMode;
  final ValueChanged<HostSortMode> onSortChanged;
  final String viewMode;
  final ValueChanged<String> onViewChanged;
  final VoidCallback? onDiscover;
  final VoidCallback? onSelect;
  final VoidCallback? onLocalTerminal;
  const _MoreMenu({
    super.key,
    required this.sortMode,
    required this.onSortChanged,
    required this.viewMode,
    required this.onViewChanged,
    this.onDiscover,
    this.onSelect,
    this.onLocalTerminal,
  });

  @override
  Widget build(BuildContext context) {
    return FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (context, controller, _) {
        FItem action(IconData icon, String title, VoidCallback? run) => FItem(
              prefix: Icon(icon),
              title: Text(title),
              onPress: () {
                controller.hide();
                run?.call();
              },
            );
        FItem choice(String title, bool on, VoidCallback run) => FItem(
              prefix: Icon(
                FLucideIcons.check,
                color: on ? YsColors.primary : Colors.transparent,
              ),
              title: Text(title),
              selected: on,
              onPress: () {
                controller.hide();
                run();
              },
            );
        return [
          FItemGroup(
            children: [
              action(FLucideIcons.radar, 'Discover', onDiscover),
              action(FLucideIcons.squareCheck, 'Select', onSelect),
              action(FLucideIcons.squareTerminal, 'Local terminal',
                  onLocalTerminal),
            ],
          ),
          FItemGroup(
            children: [
              choice('Grid', viewMode == 'grid', () => onViewChanged('grid')),
              choice('List', viewMode == 'list', () => onViewChanged('list')),
            ],
          ),
          FItemGroup(
            children: [
              for (final m in HostSortMode.values)
                choice(m.label, m == sortMode, () => onSortChanged(m)),
            ],
          ),
        ];
      },
      builder: (context, controller, _) => Tooltip(
        message: 'More actions',
        child: FButton.icon(
          variant: .outline,
          size: .sm,
          semanticsLabel: 'More actions',
          onPress: controller.toggle,
          child: const Icon(FLucideIcons.ellipsis),
        ),
      ),
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
  final bool compact;
  const _SortBtn({
    super.key,
    required this.mode,
    required this.onChanged,
    this.compact = false,
  });

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
      builder: (context, controller, _) => compact
          ? Tooltip(
              message: 'Sort: ${mode.label}',
              excludeFromSemantics: true,
              child: FButton.icon(
                variant: .outline,
                size: .sm,
                semanticsLabel: 'Sort: ${mode.label}',
                onPress: controller.toggle,
                child: const Icon(FLucideIcons.arrowDownUp),
              ),
            )
          : FButton(
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
  const _ViewToggle({super.key, required this.viewMode, required this.onChanged});

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
  final bool compact;
  const _SplitNewBtn({
    super.key,
    this.compact = false,
    required this.onNewHost,
    this.onNewGroup,
    this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          Tooltip(
            message: 'New host',
            excludeFromSemantics: true,
            child: FButton.icon(
              size: .sm,
              semanticsLabel: 'New host',
              onPress: onNewHost,
              child: const Icon(FLucideIcons.plus),
            ),
          )
        else
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
