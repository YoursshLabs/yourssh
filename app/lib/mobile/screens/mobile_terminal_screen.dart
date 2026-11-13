import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/host.dart';
import '../../models/ssh_session.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/terminal_themes.dart';
import '../../util/terminal_appearance.dart';
import '../terminal/accessory_bar_controller.dart';
import '../terminal/accessory_key_bar.dart';
import '../terminal/terminal_cursor_gestures.dart';
import '../terminal/terminal_side_panel.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../util/mobile_prefs.dart';

/// Mobile terminal screen: header + session-tab strip + xterm + accessory bar.
///
/// [focusSessionId] — if non-null, switch to that session on mount.
/// The ⋮ menu exposes [onOpenFiles] and [onOpenPortForward] hooks; these are
/// wired by Tasks 13 & 15 respectively.
class MobileTerminalScreen extends StatefulWidget {
  final String? focusSessionId;

  /// Called when the user taps "Files" in the ⋮ menu.  Receives the active
  /// session's [Host] so the caller can open the contextual SFTP screen.
  final void Function(Host host)? onOpenFiles;

  /// Called when the user taps "Port forwarding" in the ⋮ menu.  Receives the
  /// active session's [Host] so the caller can open the contextual screen.
  final void Function(Host host)? onOpenPortForward;

  const MobileTerminalScreen({
    super.key,
    this.focusSessionId,
    this.onOpenFiles,
    this.onOpenPortForward,
  });

  @override
  State<MobileTerminalScreen> createState() => _MobileTerminalScreenState();
}

class _MobileTerminalScreenState extends State<MobileTerminalScreen> {
  final _accessory = AccessoryBarController();

  /// Per-session pinch-zoom font override. Absence = follow appearance default.
  final Map<String, double> _pinch = {};
  double _scaleBase = 0;
  bool _accessoryBarEnabled = true;

  /// Whether we have already scheduled a pop-on-empty frame. Prevents double-pop
  /// when the provider fires multiple notifications in one frame.
  bool _popScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadAccessoryPref();
    if (widget.focusSessionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<SessionProvider>().setActive(widget.focusSessionId!);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ssh = context.watch<SessionProvider>().sshSessions;
    if (ssh.isEmpty && !_popScheduled) {
      _popScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.read<SessionProvider>().sshSessions.isEmpty) {
          Navigator.maybePop(context);
        }
        _popScheduled = false;
      });
    }
  }

  Future<void> _loadAccessoryPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accessoryBarEnabled = prefs.getBool(kAccessoryBarPrefKey) ?? true;
    });
  }

  @override
  void dispose() {
    _accessory.dispose();
    super.dispose();
  }

  void _onScaleStart(String sessionId, double followSize) {
    _scaleBase = _pinch[sessionId] ?? followSize;
  }

  void _onScaleUpdate(String sessionId, ScaleUpdateDetails d) {
    if (d.scale == 1.0) return;
    setState(() => _pinch[sessionId] = (_scaleBase * d.scale).clamp(8.0, 28.0));
  }

  void _openPanel(SshSession active, {int initialTab = 0}) {
    showTerminalSidePanel(
      context,
      sessionId: active.id,
      onInsert: (cmd) => active.terminal.textInput(cmd),
      onKey: (k, {ctrl = false, alt = false}) =>
          active.terminal.keyInput(k, ctrl: ctrl, alt: alt),
      initialTab: initialTab,
    );
  }

  void _showMenu(SshSession? active) {
    showFSheet<void>(
      context: context,
      side: .btt,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.folder),
              title: const Text('Files'),
              onPress: () {
                Navigator.pop(sheetCtx);
                if (widget.onOpenFiles != null && active != null) {
                  widget.onOpenFiles!(active.host);
                }
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowLeftRight),
              title: const Text('Port forwarding'),
              onPress: () {
                Navigator.pop(sheetCtx);
                if (widget.onOpenPortForward != null && active != null) {
                  widget.onOpenPortForward!(active.host);
                }
              },
            ),
            const SizedBox(height: MobileTokens.space2),
          ],
        ),
      ),
    );
  }

  /// Opens a bottom-sheet host picker so the user can start a new session
  /// without leaving the terminal. Picking a host calls [SessionProvider.connectAny].
  Future<void> _showHostPicker(BuildContext ctx) async {
    if (!mounted) return;
    await showFSheet<void>(
      context: ctx,
      side: .btt,
      builder: (sheetCtx) {
        // Read hosts inside the builder so the list is live while the sheet
        // is open (not a stale snapshot captured before the sheet opened).
        final hosts = sheetCtx.read<HostProvider>().allHosts;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileTokens.space4,
                  vertical: MobileTokens.space3,
                ),
                child: Text(
                  'Connect to host',
                  style: mobileBody(size: 16, weight: FontWeight.w600),
                ),
              ),
              if (hosts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: MobileTokens.space4),
                  child: Text(
                    'No hosts configured',
                    style: mobileBody(
                        size: 14, color: MobileColors.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: hosts.length,
                    itemBuilder: (_, i) {
                      final host = hosts[i];
                      return FItem(
                        prefix: const Icon(FLucideIcons.server),
                        title: Text(host.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${host.username}@${host.host}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mobileMono(size: 12),
                        ),
                        onPress: () {
                          Navigator.pop(sheetCtx);
                          sheetCtx.read<SessionProvider>().connectAny(host);
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: MobileTokens.space2),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final ssh = sp.sshSessions;
    // Prune pinch overrides for closed sessions.
    _pinch.removeWhere((id, _) => ssh.every((s) => s.id != id));

    if (ssh.isEmpty) {
      return Scaffold(
        backgroundColor: MobileColors.bg,
        body: Column(
          children: [
            FHeader.nested(
              title: const Text('Terminal'),
              prefixes: [
                _action(
                    'Back',
                    FHeaderAction.back(
                        onPress: () => Navigator.maybePop(context),
                        semanticsLabel: 'Back')),
              ],
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'No active sessions — connect from Hosts',
                  style: TextStyle(color: MobileColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final active = sp.activeSession is SshSession
        ? sp.activeSession as SshSession
        : ssh.last;

    final settings = context.watch<SettingsProvider>();
    final appearance = resolveTerminalAppearance(
      host: active.host,
      globalTheme: settings.terminalTheme,
      globalFont: settings.terminalFont,
      globalFontSize: settings.fontSize,
    );

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: SafeArea(
        top: false, // FHeader adds its own top safe area.
        child: Column(
          children: [
            _TerminalHeader(
              session: active,
              onBack: () => Navigator.maybePop(context),
              onMenu: () => _showMenu(active),
            ),
            _SessionTabStrip(
              sessions: ssh,
              activeId: active.id,
              onAdd: () => _showHostPicker(context),
            ),
            Expanded(
              child: _SessionBody(
                session: active,
                accessory: _accessory,
                appearance: appearance,
                fontSize: _pinch[active.id] ?? appearance.fontSize,
                accessoryBarEnabled: _accessoryBarEnabled,
                onScaleStart: (_) =>
                    _onScaleStart(active.id, appearance.fontSize),
                onScaleUpdate: (d) => _onScaleUpdate(active.id, d),
                onOpenPanel: () => _openPanel(active),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

/// Wraps an icon action in a tooltip (forui actions only carry semantics).
Widget _action(String tooltip, Widget action) =>
    Tooltip(message: tooltip, child: action);

Color _statusColor(SessionStatus status) => switch (status) {
      SessionStatus.connected => YsColors.ok,
      SessionStatus.connecting => YsColors.primary,
      _ => YsColors.error,
    };

class _TerminalHeader extends StatelessWidget {
  final SshSession session;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  const _TerminalHeader({
    required this.session,
    required this.onBack,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final label = session.host.label;
    final subtitle = '${session.host.username}@${session.host.host}';
    return FHeader.nested(
      prefixes: [
        _action('Back',
            FHeaderAction.back(onPress: onBack, semanticsLabel: 'Back')),
      ],
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: MobileTokens.statusDot,
                height: MobileTokens.statusDot,
                decoration: BoxDecoration(
                  color: _statusColor(session.status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mobileBody(size: 14, weight: FontWeight.w600)),
              ),
            ],
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mobileMono(size: 11, color: MobileColors.textMuted),
          ),
        ],
      ),
      suffixes: [
        _action(
          'More',
          FHeaderAction(
            icon: const Icon(FLucideIcons.ellipsisVertical),
            semanticsLabel: 'More',
            onPress: onMenu,
          ),
        ),
      ],
    );
  }
}

// ── Session-chip strip ────────────────────────────────────────────────────────

class _SessionTabStrip extends StatelessWidget {
  final List<SshSession> sessions;
  final String activeId;
  final VoidCallback onAdd;

  const _SessionTabStrip({
    required this.sessions,
    required this.activeId,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // 44 px chips + 2 x 4 px padding.
      height: MobileTokens.touchTarget + 8,
      color: YsColors.chrome,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _SessionTab(
                session: s,
                isActive: s.id == activeId,
                onTap: () =>
                    context.read<SessionProvider>().setActive(s.id),
                onClose: () =>
                    context.read<SessionProvider>().closeSession(s.id),
              ),
            ),
          // "+" tile
          Tooltip(
            message: 'New session',
            child: SizedBox.square(
              dimension: MobileTokens.touchTarget,
              child: FButton.icon(
                variant: .outline,
                onPress: onAdd,
                semanticsLabel: 'New session',
                child: const Icon(FLucideIcons.plus, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One session chip: status dot + label (tap = switch) and a close button
/// (tap = close). Both hit targets are >= 44 px; the label is ellipsised so a
/// long host label cannot overflow.
class _SessionTab extends StatelessWidget {
  final SshSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SessionTab({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final id = session.id;
    return Material(
      key: ValueKey('session-chip-$id'),
      color: isActive ? MobileColors.accentSoft : YsColors.card,
      shape: StadiumBorder(
        side: BorderSide(
          color: isActive ? YsColors.primary : YsColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MobileTokens.touchTarget,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: ValueKey('session-chip-label-$id'),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _statusColor(session.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        session.tabLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mobileBody(
                          size: 13,
                          color: isActive
                              ? MobileColors.textPrimary
                              : MobileColors.textMuted,
                          weight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Tooltip(
              message: 'Close session',
              child: InkWell(
                key: ValueKey('session-chip-close-$id'),
                onTap: onClose,
                child: const SizedBox.square(
                  dimension: MobileTokens.touchTarget,
                  child: Icon(FLucideIcons.x,
                      size: 14, color: MobileColors.textFaint),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Session body (terminal + accessory bar) ───────────────────────────────────

class _SessionBody extends StatefulWidget {
  final SshSession session;
  final AccessoryBarController accessory;
  final TerminalAppearance appearance;
  final double fontSize;
  final bool accessoryBarEnabled;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;
  final VoidCallback onOpenPanel;

  const _SessionBody({
    required this.session,
    required this.accessory,
    required this.appearance,
    required this.fontSize,
    required this.accessoryBarEnabled,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onOpenPanel,
  });

  @override
  State<_SessionBody> createState() => _SessionBodyState();
}

class _SessionBodyState extends State<_SessionBody> {
  final _cursor = CursorDragMapper();
  Offset _lastDrag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    if (widget.session.status == SessionStatus.connected) {
      return Column(
        children: [
          Expanded(
            // Outer GestureDetector: long-press-drag for cursor movement.
            // Inner GestureDetector: pinch-to-zoom (scale).
            // Nesting avoids competing recognizer conflicts.
            child: GestureDetector(
              onLongPressMoveUpdate: (d) {
                final delta = d.offsetFromOrigin - _lastDrag;
                for (final k in _cursor.addDelta(delta.dx, delta.dy)) {
                  widget.session.terminal.keyInput(k);
                }
                _lastDrag = d.offsetFromOrigin;
              },
              onLongPressEnd: (_) {
                _cursor.reset();
                _lastDrag = Offset.zero;
              },
              child: GestureDetector(
                onScaleStart: widget.onScaleStart,
                onScaleUpdate: widget.onScaleUpdate,
                child: ColoredBox(
                  color: MobileColors.bg,
                  child: TerminalView(
                    widget.session.terminal,
                    theme: terminalThemeByName(widget.appearance.themeName),
                    textStyle: TerminalStyle(
                      fontSize: widget.fontSize,
                      fontFamily: widget.appearance.fontFamily,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.accessoryBarEnabled)
            AccessoryKeyBar(
              controller: widget.accessory,
              onKey: (k, {ctrl = false, alt = false}) =>
                  widget.session.terminal.keyInput(k, ctrl: ctrl, alt: alt),
              onText: (s) => widget.session.terminal.textInput(s),
              onOpenPanel: widget.onOpenPanel,
            ),
        ],
      );
    }

    // Non-connected state: progress/status/error.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.session.status == SessionStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: FCircularProgress(),
            ),
          Text(
            widget.session.statusLabel,
            style: const TextStyle(color: MobileColors.textMuted),
          ),
          if (widget.session.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.session.errorMessage!,
              style: const TextStyle(
                  color: MobileColors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
