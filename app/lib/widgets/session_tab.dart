import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/agent_forwarding_state.dart';
import '../models/session_health.dart';
import '../models/ssh_session.dart';
import '../models/terminal_session.dart';
import '../providers/host_provider.dart';
import '../providers/recording_provider.dart';
import '../providers/session_provider.dart';
import '../providers/shell_integration_provider.dart';
import '../services/health_monitor_service.dart';
import '../services/os_detection.dart';
import '../theme/app_theme.dart';
import 'health_dot.dart';

class SessionTab extends StatefulWidget {
  final AppSession session;
  final bool isActive;
  final SessionProvider provider;
  final VoidCallback onTap;
  const SessionTab({super.key, required this.session, required this.isActive, required this.provider, required this.onTap});

  @override
  State<SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<SessionTab> {
  bool _hovered = false;
  bool _isRenaming = false;
  late TextEditingController _renameController;

  @override
  void initState() {
    super.initState();
    _renameController = TextEditingController();
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  void _startRename() {
    _renameController.text = widget.session.tabLabel;
    _renameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _renameController.text.length,
    );
    setState(() => _isRenaming = true);
  }

  void _commitRename() {
    final text = _renameController.text.trim();
    widget.provider.renameSession(
      widget.session.id,
      text.isEmpty ? null : text,
    );
    setState(() => _isRenaming = false);
  }

  /// Tab label, appending the shell-integration cwd basename when known and
  /// the user hasn't set a custom label.
  String _composedLabel(BuildContext context) {
    final base = widget.session.tabLabel;
    if (widget.session.customLabel != null) return base;
    // select scopes the rebuild to this session's cwd (provider notifies globally).
    final cwd = context.select<ShellIntegrationProvider, String?>(
        (s) => s.cwdFor(widget.session.id));
    if (cwd == null || cwd.isEmpty) return base;
    final name = p.posix.basename(cwd);
    return '$base · ${name.isEmpty ? '/' : name}';
  }

  Future<void> _showTabContextMenu(BuildContext context, Offset globalPos) async {
    final session = widget.session;
    final provider = widget.provider;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: const Row(children: [
            Icon(Icons.edit_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('Rename', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Row(children: [
            Icon(
              session.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 14,
              color: const Color(0xFFAAAAAA),
            ),
            const SizedBox(width: 8),
            Text(
              session.isPinned ? 'Unpin' : 'Pin',
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
            ),
          ]),
        ),
        PopupMenuItem(
          value: 'color',
          child: const Row(children: [
            Icon(Icons.circle_outlined, size: 14, color: Color(0xFFAAAAAA)),
            SizedBox(width: 8),
            Text('Color tag', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
            Spacer(),
            Icon(Icons.chevron_right, size: 14, color: Color(0xFF666666)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          child: const Row(children: [
            Icon(Icons.close, size: 14, color: Color(0xFF888888)),
            SizedBox(width: 8),
            Text('Close', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
          ]),
        ),
      ],
    );

    if (!context.mounted) return;

    switch (result) {
      case 'rename':
        _startRename();
      case 'pin':
        provider.togglePin(session.id);
      case 'color':
        await _showColorSubmenu(context, globalPos);
      case 'close':
        provider.closeSession(session.id);
    }
  }

  Future<void> _showColorSubmenu(BuildContext context, Offset globalPos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx + 160, globalPos.dy + 60,
        globalPos.dx + 161, globalPos.dy + 61,
      ),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        PopupMenuItem(
          value: 'none',
          child: const Row(children: [
            SizedBox(
              width: 14, height: 14,
              child: Icon(Icons.block, size: 12, color: Color(0xFF666666)),
            ),
            SizedBox(width: 8),
            Text('None', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
          ]),
        ),
        ...AppColors.tabColors.map((c) => PopupMenuItem(
          value: c.$2,
          child: Row(children: [
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: AppColors.fromHex(c.$2),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(c.$1, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
          ]),
        )),
      ],
    );

    if (result != null) {
      widget.provider.setSessionColor(
        widget.session.id,
        result == 'none' ? null : result,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = widget.isActive ? AppColors.accent : const Color(0xFF888888);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          widget.provider.setActive(widget.session.id);
          widget.onTap();
        },
        onDoubleTap: _startRename,
        onSecondaryTapUp: (details) =>
            _showTabContextMenu(context, details.globalPosition),
        // Middle-click closes the tab; pinned tabs are protected (consistent
        // with the hidden X button — close stays reachable via the menu).
        onTertiaryTapUp: widget.session.isPinned
            ? null
            : (_) => widget.provider.closeSession(widget.session.id),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFF1C1C1C)
                : _hovered
                    ? const Color(0xFF141414)
                    : Colors.transparent,
            border: widget.isActive
                ? const Border(bottom: BorderSide(color: AppColors.accent, width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Connection health dot for SSH (hidden for watch sessions);
              // laptop glyph for local tabs.
              if (widget.session case final SshSession ssh
                  when !ssh.isWatch)
                Builder(builder: (context) {
                  final health = context
                      .watch<HealthMonitorService>()
                      .healthFor(ssh.host.id);
                  final tone = badgeToneFor(ssh.status, health);
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Tooltip(
                      message: _healthTooltip(ssh, health),
                      child: HealthDot(tone: tone),
                    ),
                  );
                })
              else if (widget.session case TerminalSession ts when ts.isLocal)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(Icons.laptop_mac,
                      size: 12, color: Color(0xFF888888)),
                ),
              // Distro/OS glyph — reads detectedOs from HostProvider (the
              // session's Host snapshot goes stale after copyWith on detect).
              if (widget.session case final SshSession ssh when !ssh.isWatch)
                Builder(builder: (context) {
                  final os = context.select<HostProvider, String?>((hp) {
                    for (final h in hp.allHosts) {
                      if (h.id == ssh.host.id) return h.detectedOs;
                    }
                    return null;
                  });
                  final asset = osIconAsset(os);
                  if (asset == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: SvgPicture.asset(
                      asset,
                      width: 14,
                      height: 14,
                      colorFilter: const ColorFilter.mode(
                          Color(0xFF888888), BlendMode.srcIn),
                    ),
                  );
                }),
              // Red recording indicator
              Consumer<RecordingProvider>(
                builder: (context, rec, _) => rec.isRecording(widget.session.id)
                    ? Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // Agent-forwarding key icon — only for sessions whose host
              // opted in (state != off), colored by live state.
              if (widget.session case final SshSession ssh
                  when ssh.agentForwardingState != AgentForwardingState.off)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Tooltip(
                    message: agentForwardingTooltip(ssh.agentForwardingState),
                    child: Icon(Icons.key,
                        size: 12,
                        color:
                            agentForwardingColor(ssh.agentForwardingState)),
                  ),
                ),
              // Color dot (shown when colorTag is set)
              if (widget.session.colorTag != null)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: AppColors.fromHex(widget.session.colorTag!),
                    shape: BoxShape.circle,
                  ),
                ),
              // X close button — hidden when pinned
              if (!widget.session.isPinned)
                GestureDetector(
                  onTap: () => widget.provider.closeSession(widget.session.id),
                  child: Icon(
                    Icons.close,
                    size: 11,
                    color: _hovered || widget.isActive ? const Color(0xFF888888) : const Color(0xFF444444),
                  ),
                ),
              const SizedBox(width: 8),
              // Host label — switches to Focus+TextField when renaming
              if (_isRenaming)
                SizedBox(
                  width: 100,
                  height: 20,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        setState(() => _isRenaming = false);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _renameController,
                      autofocus: true,
                      style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 12),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _commitRename(),
                      onTapOutside: (_) => _commitRename(),
                      // Suppress default focus-traversal on Enter; commit is
                      // handled by onSubmitted/onTapOutside.
                      onEditingComplete: () {},
                    ),
                  ),
                )
              else
                Text(
                  _composedLabel(context),
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              const SizedBox(width: 8),
              // Pin icon (shown when pinned)
              if (widget.session.isPinned)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.push_pin, size: 11, color: Color(0xFF888888)),
                ),
              // Terminal icon (right)
              Icon(
                Icons.monitor_outlined,
                size: 13,
                color: widget.isActive ? AppColors.accent : const Color(0xFF555555),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _healthTooltip(SshSession session, SessionHealth health) {
  final latency = health.latencyMs != null ? '${health.latencyMs}ms' : '—';
  final word = switch (health.status) {
    HealthStatus.healthy => 'healthy',
    HealthStatus.degraded => 'degraded',
    HealthStatus.down => 'down',
    HealthStatus.offline => 'connecting…',
  };
  final uptime = _fmtDuration(DateTime.now().difference(session.connectedAt));
  final ping = health.lastPingAt != null
      ? '${DateTime.now().difference(health.lastPingAt!).inSeconds}s ago'
      : '—';
  return '${session.title}\n'
      '$latency · $word\n'
      'Uptime $uptime · last ping $ping\n'
      'Reconnects this session: ${session.reconnectCount}';
}

String _fmtDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// Tab key-icon color per live forwarding state (off renders no icon).
Color agentForwardingColor(AgentForwardingState state) => switch (state) {
      AgentForwardingState.ready => AppColors.textSecondary,
      AgentForwardingState.active => AppColors.accent,
      AgentForwardingState.fallback => AppColors.orange,
      AgentForwardingState.refused => AppColors.red,
      // Unreachable from the tab (the icon is gated on state != off); kept
      // only to keep the switch exhaustive.
      AgentForwardingState.off => Colors.transparent,
    };

String agentForwardingTooltip(AgentForwardingState state) => switch (state) {
      AgentForwardingState.ready =>
        'Agent forwarding ready — no key requests from this host yet',
      AgentForwardingState.active =>
        'Agent forwarding active — serving keys from your system agent',
      AgentForwardingState.fallback =>
        'Agent forwarding active — serving app Keychain keys (no system agent found)',
      AgentForwardingState.refused =>
        'Agent forwarding refused by server (AllowAgentForwarding no)',
      AgentForwardingState.off => '',
    };
