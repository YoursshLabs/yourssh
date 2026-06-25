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
import '../terminal/mobile_snippets_sheet.dart';

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

  void _openSnippets(SshSession active) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (_) => MobileSnippetsSheet(
        onInsert: (cmd) => active.terminal.textInput(cmd),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final ssh = sp.sshSessions;

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
                  icon: const Icon(Icons.code, color: AppColors.textSecondary),
                  tooltip: 'Snippets',
                  onPressed: () => _openSnippets(active),
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
              child: ChoiceChip(
                label: Text(s.tabLabel),
                selected: s.id == activeId,
                onSelected: (_) =>
                    context.read<SessionProvider>().setActive(s.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  final SshSession session;
  final AccessoryBarController accessory;
  final TerminalAppearance appearance;
  final double fontSize;
  final void Function(ScaleStartDetails) onScaleStart;
  final void Function(ScaleUpdateDetails) onScaleUpdate;

  const _SessionBody({
    required this.session,
    required this.accessory,
    required this.appearance,
    required this.fontSize,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (session.status == SessionStatus.connected) {
      return Column(
        children: [
          Expanded(
            child: GestureDetector(
              onScaleStart: onScaleStart,
              onScaleUpdate: onScaleUpdate,
              child: TerminalView(
                session.terminal,
                theme: terminalThemeByName(appearance.themeName),
                textStyle: TerminalStyle(
                  fontSize: fontSize,
                  fontFamily: appearance.fontFamily,
                ),
              ),
            ),
          ),
          AccessoryKeyBar(
            controller: accessory,
            onKey: (k, {ctrl = false, alt = false}) =>
                session.terminal.keyInput(k, ctrl: ctrl, alt: alt),
            onText: (s) => session.terminal.textInput(s),
          ),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.status == SessionStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(),
            ),
          Text(session.statusLabel,
              style: const TextStyle(color: AppColors.textSecondary)),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(session.errorMessage!,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
