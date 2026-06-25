import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../models/ssh_session.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/terminal_themes.dart';
import '../../util/terminal_appearance.dart';
import '../terminal/accessory_bar_controller.dart';
import '../terminal/accessory_key_bar.dart';
import '../terminal/terminal_cursor_gestures.dart';
import '../terminal/terminal_side_panel.dart';
import '../theme/mobile_tokens.dart';

/// Sessions tab: a session strip + the active SSH session's terminal (when
/// connected, with the accessory key bar docked below and per-session
/// pinch-to-zoom) or its connection status.
class MobileSessionsScreen extends StatefulWidget {
  const MobileSessionsScreen({super.key});

  @override
  State<MobileSessionsScreen> createState() => _MobileSessionsScreenState();
}

class _MobileSessionsScreenState extends State<MobileSessionsScreen> {
  final _accessory = AccessoryBarController();
  // Pinch-zoom font overrides, keyed by session id — so zooming one session
  // doesn't bleed its size onto another (and absence = follow appearance).
  final Map<String, double> _pinch = {};
  double _scaleBase = 0;

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

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final ssh = sp.sshSessions;
    // Drop pinch-zoom overrides for sessions that have since closed.
    _pinch.removeWhere((id, _) => ssh.every((s) => s.id != id));

    if (ssh.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('No active sessions — connect from Hosts',
              style: TextStyle(color: AppColors.textSecondary)),
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
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: _SessionStrip(sessions: ssh, activeId: active.id)),
                IconButton(
                  icon: const Icon(Icons.dashboard_customize_outlined,
                      color: AppColors.textSecondary),
                  tooltip: 'Keyboard, snippets, history, themes',
                  onPressed: () => _openPanel(active),
                ),
              ],
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _SessionBody(
                session: active,
                accessory: _accessory,
                appearance: appearance,
                fontSize: _pinch[active.id] ?? appearance.fontSize,
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

class _SessionStrip extends StatelessWidget {
  final List<SshSession> sessions;
  final String activeId;
  const _SessionStrip({required this.sessions, required this.activeId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _SessionPill(
                session: s,
                selected: s.id == activeId,
                onTap: () => context.read<SessionProvider>().setActive(s.id),
                onClose: () => context.read<SessionProvider>().closeSession(s.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionPill extends StatelessWidget {
  final SshSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _SessionPill({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.card : AppColors.bg,
          borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.hostColor(session.host.host),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(session.tabLabel,
                style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionBody extends StatefulWidget {
  final SshSession session;
  final AccessoryBarController accessory;
  final TerminalAppearance appearance;
  final double fontSize;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;
  final VoidCallback onOpenPanel;

  const _SessionBody({
    required this.session,
    required this.accessory,
    required this.appearance,
    required this.fontSize,
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
            // Outer GestureDetector handles long-press-drag for cursor movement.
            // Inner GestureDetector handles pinch-to-zoom (scale).
            // Nesting avoids competing recognizer conflicts between scale and
            // long-press-drag that can occur with a single GestureDetector.
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.session.status == SessionStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(),
            ),
          Text(widget.session.statusLabel,
              style: const TextStyle(color: AppColors.textSecondary)),
          if (widget.session.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(widget.session.errorMessage!,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
