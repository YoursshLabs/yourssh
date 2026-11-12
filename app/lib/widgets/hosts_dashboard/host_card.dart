part of 'hosts_dashboard.dart';

// ── Host Card ─────────────────────────────────────────────

/// One host on the dashboard, over [YsHostCard]. Shared by the grid and the
/// list ([compact]).
///
/// Mouse: double-click connects (outside select mode); a click toggles the
/// selection in select mode. Keyboard: Enter/Space on the focused card does
/// the same — connect, or toggle in select mode. The hover actions (Test,
/// SFTP, Monitor, More) also show while the card has keyboard focus, so Tab
/// reaches them. Select mode has one tab stop per card: the checkbox is not
/// focusable (Enter/Space on the card toggles).
class _HostCard extends StatefulWidget {
  final Host host;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  /// Open tabs for this host, whether one is connected, and whether an SSH
  /// tab is open (Monitor).
  final int openSessions;
  final bool live;
  final bool hasSshSession;

  /// false → grid card; true → full-width list row (no tags, smaller tile).
  final bool compact;
  const _HostCard({
    super.key,
    required this.host,
    this.onEditHost,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.openSessions = 0,
    this.live = false,
    this.hasSshSession = false,
    this.compact = false,
  });

  @override
  State<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<_HostCard> {
  bool _hovered = false;
  bool _focusWithin = false;
  bool _menuOpen = false;
  bool _testing = false;
  ({bool success, int latencyMs, String? error})? _testResult;
  Timer? _resultTimer;
  final _cardFocus = FocusNode(debugLabel: 'host-card');

  @override
  void dispose() {
    _resultTimer?.cancel();
    _cardFocus.dispose();
    super.dispose();
  }

  void _setMenuOpen(bool open) {
    if (mounted && open != _menuOpen) setState(() => _menuOpen = open);
  }

  void _connect() => context.read<SessionProvider>().connectAny(widget.host);

  Widget _osGlyph(double size) {
    final asset = osIconAsset(widget.host.detectedOs);
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: size * 0.55,
        height: size * 0.55,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
    }
    return const Icon(FLucideIcons.server);
  }

  Future<void> _test() async {
    if (_testing) return;
    _resultTimer?.cancel();
    // The spinner replaces the action buttons; if one of them has keyboard
    // focus, hand it to the card so focus is not dropped.
    if (_cardFocus.hasFocus && !_cardFocus.hasPrimaryFocus) {
      _cardFocus.requestFocus();
    }
    setState(() { _testing = true; _testResult = null; });

    final sshService = context.read<SshService>();
    final storage = context.read<StorageService>();
    final keyProvider = context.read<KeyProvider>();
    final keys = keyProvider.keys;
    // Read all providers before the first await (no BuildContext across gaps).
    final hostsById = {
      for (final h in context.read<HostProvider>().allHosts) h.id: h
    };

    final password = widget.host.authType == AuthType.password
        ? await storage.loadPassword(widget.host.id)
        : null;

    SshKeyEntry? keyEntry;
    if (widget.host.authType == AuthType.privateKey && widget.host.keyId != null) {
      keyEntry = keys.where((k) => k.id == widget.host.keyId).firstOrNull;
    }

    // Test through the bastion chain, not a misleading direct dial.
    List<JumpHop> jumpChain;
    try {
      jumpChain = SshService.resolveJumpChain(
        widget.host,
        jumpLookup: (id) => hostsById[id],
        keyLookup: (id) => keyProvider.findById(id),
      );
    } on JumpChainException catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = (success: false, latencyMs: 0, error: e.message);
        });
      }
      return;
    }

    final result = await sshService.testConnection(
      widget.host,
      password: password,
      keyEntry: keyEntry,
      jumpChain: jumpChain,
    );

    if (!mounted) return;
    setState(() { _testing = false; _testResult = result; });
    _resultTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _testResult = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final tileSize = widget.compact ? 28.0 : 36.0;
    final port = host.port == 22 ? '' : ':${host.port}';
    final n = widget.openSessions;

    Widget leading = YsOsTile(
      glyph: _osGlyph(tileSize),
      color: AppColors.hostColor(host.id),
      size: tileSize,
    );
    if (widget.selectionMode) {
      leading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Not a tab stop: Enter/Space on the card toggles the selection.
          ExcludeFocus(
            child: FCheckbox(
              key: const Key('host-card-checkbox'),
              value: widget.selected,
              semanticsLabel: 'Select ${host.label}',
              onChange: (_) => widget.onToggleSelect?.call(),
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          leading,
        ],
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: (f) {
          if (mounted) setState(() => _focusWithin = f);
        },
        child: YsHostCard(
          leading: leading,
          title: host.label,
          subtitle: '${host.username}@${host.host}$port',
          statusDot: Container(
            key: const Key('host-status-dot'),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.live ? YsColors.ok : YsColors.off,
              shape: BoxShape.circle,
            ),
          ),
          badges: [
            if (host.protocol != HostProtocol.ssh) ProtocolBadge(host.protocol),
          ],
          tags: widget.compact ? const [] : [for (final t in host.tags) YsTag(t)],
          meta: n == 0 ? null : '$n session${n == 1 ? '' : 's'}',
          selected: widget.selectionMode && widget.selected,
          onTap: widget.selectionMode ? widget.onToggleSelect : null,
          onDoubleTap: widget.selectionMode ? null : _connect,
          onActivate: widget.selectionMode ? widget.onToggleSelect : _connect,
          focusNode: _cardFocus,
          trailingAction: _trailing(context),
        ),
      ),
    );
  }

  /// Hover/focus actions, spinner or test result — shared by both layouts.
  Widget? _trailing(BuildContext context) {
    final showActions = !widget.selectionMode &&
        (_hovered || _focusWithin || _menuOpen) &&
        !_testing &&
        _testResult == null;
    final result = _testResult;
    if (_testing) {
      return const FCircularProgress(size: .sm);
    }
    if (result != null) {
      final color = result.success ? YsColors.ok : YsColors.error;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.compact ? 260 : 120),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              result.success ? FLucideIcons.circleCheck : FLucideIcons.circleAlert,
              size: 14,
              color: color,
            ),
            const SizedBox(width: YsSpace.s1),
            Flexible(
              child: Text(
                result.success
                    ? '${result.latencyMs}ms'
                    : (result.error ?? 'Failed'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }
    if (!showActions) return null;
    // Test/SFTP drive an SSH handshake — meaningless against an RDP port.
    final isSsh = widget.host.protocol == HostProtocol.ssh;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSsh) ...[
          _iconBtn(FLucideIcons.activity, 'Test connection', _test),
          _iconBtn(FLucideIcons.folder, 'SFTP', () => _openSftp(context)),
          if (widget.hasSshSession)
            _iconBtn(FLucideIcons.heartPulse, 'Monitor',
                () => ServerMonitorSheet.show(context, widget.host)),
        ],
        _moreMenu(),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onPress) =>
      Tooltip(
        message: tooltip,
        child: FButton.icon(
          variant: .ghost,
          size: .xs,
          onPress: onPress,
          child: Icon(icon),
        ),
      );

  Widget _moreMenu() {
    HostProvider hosts() => context.read<HostProvider>();
    final isSsh = widget.host.protocol == HostProtocol.ssh;
    FItem item(FPopoverController c, IconData icon, String label,
            VoidCallback action, {bool destructive = false}) =>
        FItem(
          variant: destructive ? .destructive : .primary,
          prefix: Icon(icon),
          title: Text(label),
          onPress: () {
            c.hide();
            action();
          },
        );
    return FPopoverMenu(
      control: FPopoverControl.managed(onChange: _setMenuOpen),
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      // Actions use the card's context: the menu's own context unmounts once
      // the menu finishes hiding (e.g. before Copy URL's await returns).
      menuBuilder: (_, c, _) => [
        FItemGroup(children: [
          item(c, FLucideIcons.squareTerminal, 'Connect', _connect),
          if (isSsh)
            item(c, FLucideIcons.folder, 'SFTP', () => _openSftp(context)),
          if (isSsh)
            item(c, FLucideIcons.heartPulse, 'Monitor',
                () => ServerMonitorSheet.show(context, widget.host)),
          item(c, FLucideIcons.pencil, 'Edit',
              () => widget.onEditHost?.call(widget.host)),
        ]),
        FItemGroup(children: [
          item(c, FLucideIcons.copy, 'Duplicate',
              () => _duplicate(context, hosts())),
          item(c, FLucideIcons.link,
              'Copy ${widget.host.protocol.name.toUpperCase()} URL',
              () => _copyHostUrl(context)),
          item(c, FLucideIcons.folderInput, 'Move to group',
              () => _moveToGroup(context, hosts())),
          item(c, FLucideIcons.upload, 'Export', () => _export(context)),
        ]),
        FItemGroup(children: [
          item(c, FLucideIcons.trash2, 'Delete',
              () => hosts().deleteHost(widget.host.id),
              destructive: true),
        ]),
      ],
      builder: (_, c, _) => Tooltip(
        message: 'More',
        child: FButton.icon(
          variant: .ghost,
          size: .xs,
          onPress: c.toggle,
          child: const Icon(FLucideIcons.ellipsis),
        ),
      ),
    );
  }

  Future<void> _copyHostUrl(BuildContext context) async {
    final scheme = switch (widget.host.protocol) {
      HostProtocol.rdp => 'rdp',
      HostProtocol.vnc => 'vnc',
      HostProtocol.ssh => 'ssh',
    };
    final url = '$scheme://${widget.host.username}@${widget.host.host}:${widget.host.port}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    showYsToast(context, '${scheme.toUpperCase()} URL copied',
        duration: const Duration(seconds: 2));
  }

  Future<void> _duplicate(BuildContext context, HostProvider hostProvider) async {
    final copy = Host(
      label: '${widget.host.label} (copy)',
      host: widget.host.host,
      port: widget.host.port,
      username: widget.host.username,
      protocol: widget.host.protocol,
      domain: widget.host.domain,
      rdpSecurity: widget.host.rdpSecurity,
      remoteClipboard: widget.host.remoteClipboard,
      authType: widget.host.authType,
      keyId: widget.host.keyId,
      group: widget.host.group,
      tags: List<String>.from(widget.host.tags),
      jumpHostIds: List<String>.from(widget.host.jumpHostIds),
      sftpMode: widget.host.sftpMode,
      sftpServerCommand: widget.host.sftpServerCommand,
    );
    await hostProvider.addHost(copy);
    if (!context.mounted) return;
    widget.onEditHost?.call(copy);
  }

  void _moveToGroup(BuildContext context, HostProvider hostProvider) {
    final groups = hostProvider.allHosts
        .map((h) => h.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    showYsDialog<void>(
      context,
      builder: (_) => _MoveToGroupDialog(
        host: widget.host,
        groups: groups,
        onSelect: (g) => hostProvider.updateHost(widget.host.copyWith(group: g)),
      ),
    );
  }

  void _export(BuildContext context) {
    showYsDialog<void>(context, builder: (_) => _ExportDialog(host: widget.host));
  }

  void _openSftp(BuildContext context) {
    showYsDialog<void>(
      context,
      barrierDismissible: false,
      builder: (_) => YsDialogFrame(
        maxWidth: 800,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 800,
          height: 600,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(YsRadius.card),
            child: SftpScreen(host: widget.host),
          ),
        ),
      ),
    );
  }
}
