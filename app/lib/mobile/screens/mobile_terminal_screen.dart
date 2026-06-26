import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

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
/// wired by Tasks 13 & 15 respectively. Passing null shows a "coming soon"
/// SnackBar as an interim stub.
class MobileTerminalScreen extends StatefulWidget {
  final String? focusSessionId;

  /// Called when the user taps "Files" in the ⋮ menu.  Receives the active
  /// session's [Host] so the caller can open the contextual SFTP screen.
  final void Function(Host host)? onOpenFiles;
  final VoidCallback? onOpenPortForward;

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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MobileColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MobileColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.folder_outlined,
                  color: MobileColors.textPrimary),
              title: Text('Files',
                  style: mobileBody(color: MobileColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                if (widget.onOpenFiles != null && active != null) {
                  widget.onOpenFiles!(active.host);
                } else if (widget.onOpenFiles == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Files — coming soon')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.compare_arrows_outlined,
                  color: MobileColors.textPrimary),
              title: Text('Port forwarding',
                  style: mobileBody(color: MobileColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                if (widget.onOpenPortForward != null) {
                  widget.onOpenPortForward!();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Port forwarding — coming soon')),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Opens a bottom-sheet host picker so the user can start a new session
  /// without leaving the terminal. Picking a host calls [SessionProvider.connectAny].
  Future<void> _showHostPicker(BuildContext ctx) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: MobileColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        // Read hosts inside the builder so the list is live while the sheet
        // is open (not a stale snapshot captured before the sheet opened).
        final hosts = sheetCtx.read<HostProvider>().allHosts;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MobileColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                ListView.builder(
                  shrinkWrap: true,
                  itemCount: hosts.length,
                  itemBuilder: (_, i) {
                    final host = hosts[i];
                    return ListTile(
                      leading: const Icon(Icons.dns_outlined,
                          color: MobileColors.textPrimary),
                      title: Text(host.label,
                          style: mobileBody(
                              size: 15, color: MobileColors.textPrimary)),
                      subtitle: Text(
                        '${host.username}@${host.host}',
                        style: mobileMono(
                            size: 12, color: MobileColors.textMuted),
                      ),
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        sheetCtx.read<SessionProvider>().connectAny(host);
                      },
                    );
                  },
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
        appBar: AppBar(
          backgroundColor: MobileColors.surfaceAlt,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: MobileColors.accent, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text('Terminal',
              style: mobileBody(size: 16, weight: FontWeight.w600)),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'No active sessions — connect from Hosts',
            style: TextStyle(color: MobileColors.textMuted),
          ),
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
    return Container(
      height: 52,
      color: MobileColors.surfaceAlt,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: MobileColors.accent, size: 20),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: session.status == SessionStatus.connected
                            ? MobileColors.green
                            : session.status == SessionStatus.connecting
                                ? MobileColors.accent
                                : MobileColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(label,
                        style: mobileBody(
                            size: 14, weight: FontWeight.w600)),
                  ],
                ),
                Text(
                  subtitle,
                  style: mobileMono(
                      size: 11, color: MobileColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_split_outlined,
                color: MobileColors.textMuted, size: 20),
            tooltip: 'Split',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert,
                color: MobileColors.textMuted, size: 20),
            tooltip: 'More',
            onPressed: onMenu,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Session-tab strip ─────────────────────────────────────────────────────────

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
      height: 44,
      color: MobileColors.surfaceAlt,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
          GestureDetector(
            onTap: onAdd,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: MobileColors.surface,
                borderRadius:
                    BorderRadius.circular(MobileTokens.radiusPill),
                border: Border.all(color: MobileColors.border),
              ),
              child: const Icon(Icons.add,
                  size: 16, color: MobileColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? MobileColors.accentSoft : MobileColors.surface,
          borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
          border: Border.all(
            color: isActive ? MobileColors.accent : MobileColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: MobileColors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              session.tabLabel,
              style: mobileBody(
                size: 13,
                color: isActive
                    ? MobileColors.textPrimary
                    : MobileColors.textMuted,
                weight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close,
                  size: 14, color: MobileColors.textFaint),
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
              child: CircularProgressIndicator(color: MobileColors.accent),
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
