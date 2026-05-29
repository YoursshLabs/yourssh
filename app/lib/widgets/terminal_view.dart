import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../models/ssh_session.dart';
import '../providers/settings_provider.dart';

class SessionTerminalView extends StatelessWidget {
  final SshSession session;
  const SessionTerminalView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return switch (session.status) {
      SessionStatus.connecting => _statusView(Icons.sync, 'Connecting to ${session.host.host}…', Colors.orange),
      SessionStatus.error => _statusView(Icons.error_outline, session.errorMessage ?? 'Connection error', Colors.red),
      SessionStatus.disconnected => _statusView(Icons.link_off, 'Disconnected', Colors.grey),
      SessionStatus.connected => _TerminalWidget(session: session),
    };
  }

  Widget _statusView(IconData icon, String message, Color color) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _TerminalWidget extends StatelessWidget {
  final SshSession session;
  const _TerminalWidget({required this.session});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = _themeFor(settings.terminalTheme);

    return TerminalView(
      session.terminal,
      theme: theme,
      textStyle: TerminalStyle(
        fontSize: settings.fontSize,
        fontFamily: 'monospace',
      ),
      padding: EdgeInsets.zero,
      autofocus: true,
    );
  }

  static TerminalTheme _themeFor(String name) {
    return switch (name) {
      'One Dark' => _oneDark,
      'Tokyo Night' => _tokyoNight,
      'Nord' => _nord,
      'Solarized Dark' => _solarizedDark,
      _ => _dracula, // Dracula default
    };
  }
}

// ── Terminal Themes ───────────────────────────────────────

const _dracula = TerminalTheme(
  cursor: Color(0xFFCCCCCC),
  selection: Color(0xFF44475A),
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF282A36),
  black: Color(0xFF21222C),
  red: Color(0xFFFF5555),
  green: Color(0xFF50FA7B),
  yellow: Color(0xFFF1FA8C),
  blue: Color(0xFFBD93F9),
  magenta: Color(0xFFFF79C6),
  cyan: Color(0xFF8BE9FD),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF6272A4),
  brightRed: Color(0xFFFF6E6E),
  brightGreen: Color(0xFF69FF94),
  brightYellow: Color(0xFFFFFFA5),
  brightBlue: Color(0xFFD6ACFF),
  brightMagenta: Color(0xFFFF92DF),
  brightCyan: Color(0xFFA4FFFF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFB86C),
  searchHitBackgroundCurrent: Color(0xFFFF5555),
  searchHitForeground: Color(0xFF282A36),
);

const _oneDark = TerminalTheme(
  cursor: Color(0xFFABB2BF),
  selection: Color(0xFF3E4451),
  foreground: Color(0xFFABB2BF),
  background: Color(0xFF282C34),
  black: Color(0xFF282C34),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFABB2BF),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFE5C07B),
  searchHitBackgroundCurrent: Color(0xFFE06C75),
  searchHitForeground: Color(0xFF282C34),
);

const _tokyoNight = TerminalTheme(
  cursor: Color(0xFFC0CAF5),
  selection: Color(0xFF364A82),
  foreground: Color(0xFFC0CAF5),
  background: Color(0xFF1A1B26),
  black: Color(0xFF15161E),
  red: Color(0xFFF7768E),
  green: Color(0xFF9ECE6A),
  yellow: Color(0xFFE0AF68),
  blue: Color(0xFF7AA2F7),
  magenta: Color(0xFFBB9AF7),
  cyan: Color(0xFF7DCFFF),
  white: Color(0xFFA9B1D6),
  brightBlack: Color(0xFF414868),
  brightRed: Color(0xFFF7768E),
  brightGreen: Color(0xFF9ECE6A),
  brightYellow: Color(0xFFE0AF68),
  brightBlue: Color(0xFF7AA2F7),
  brightMagenta: Color(0xFFBB9AF7),
  brightCyan: Color(0xFF7DCFFF),
  brightWhite: Color(0xFFC0CAF5),
  searchHitBackground: Color(0xFFE0AF68),
  searchHitBackgroundCurrent: Color(0xFFF7768E),
  searchHitForeground: Color(0xFF1A1B26),
);

const _nord = TerminalTheme(
  cursor: Color(0xFFD8DEE9),
  selection: Color(0xFF434C5E),
  foreground: Color(0xFFD8DEE9),
  background: Color(0xFF2E3440),
  black: Color(0xFF3B4252),
  red: Color(0xFFBF616A),
  green: Color(0xFFA3BE8C),
  yellow: Color(0xFFEBCB8B),
  blue: Color(0xFF81A1C1),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF88C0D0),
  white: Color(0xFFE5E9F0),
  brightBlack: Color(0xFF4C566A),
  brightRed: Color(0xFFBF616A),
  brightGreen: Color(0xFFA3BE8C),
  brightYellow: Color(0xFFEBCB8B),
  brightBlue: Color(0xFF81A1C1),
  brightMagenta: Color(0xFFB48EAD),
  brightCyan: Color(0xFF8FBCBB),
  brightWhite: Color(0xFFECEFF4),
  searchHitBackground: Color(0xFFEBCB8B),
  searchHitBackgroundCurrent: Color(0xFFBF616A),
  searchHitForeground: Color(0xFF2E3440),
);

const _solarizedDark = TerminalTheme(
  cursor: Color(0xFF839496),
  selection: Color(0xFF073642),
  foreground: Color(0xFF839496),
  background: Color(0xFF002B36),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF586E75),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: Color(0xFFB58900),
  searchHitBackgroundCurrent: Color(0xFFDC322F),
  searchHitForeground: Color(0xFF002B36),
);
