// app/lib/widgets/local_terminal_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../providers/local_session_provider.dart';
import '../providers/settings_provider.dart';
import '../models/local_session.dart';

class LocalTerminalScreen extends StatefulWidget {
  const LocalTerminalScreen({super.key});

  @override
  State<LocalTerminalScreen> createState() => _LocalTerminalScreenState();
}

class _LocalTerminalScreenState extends State<LocalTerminalScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-open first session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LocalSessionProvider>();
      if (provider.sessions.isEmpty) {
        provider.newSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalSessionProvider>();

    return Column(
      children: [
        _buildTabBar(provider),
        Expanded(child: _buildTerminal(provider)),
      ],
    );
  }

  Widget _buildTabBar(LocalSessionProvider provider) {
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      child: Row(
        children: [
          ...provider.sessions.map((s) => _buildTab(s, provider)),
          IconButton(
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF888888)),
            onPressed: provider.newSession,
            tooltip: 'New local shell',
          ),
        ],
      ),
    );
  }

  Widget _buildTab(LocalSession session, LocalSessionProvider provider) {
    final isActive = provider.activeSession?.id == session.id;
    return GestureDetector(
      onTap: () => provider.setActive(session.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1C1C1C) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF22C55E) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 14, color: Color(0xFF888888)),
            const SizedBox(width: 6),
            const Text('Local', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 13)),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => provider.closeSession(session.id),
              child: const Icon(Icons.close, size: 12, color: Color(0xFF555555)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal(LocalSessionProvider provider) {
    final session = provider.activeSession;
    if (session == null) {
      return const Center(
        child: Text('No local session', style: TextStyle(color: Color(0xFF555555))),
      );
    }
    if (session.status == LocalSessionStatus.error) {
      return Center(
        child: Text(
          session.errorMessage ?? 'Unknown error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    final settings = context.watch<SettingsProvider>();
    return TerminalView(
      key: ValueKey(session.id),
      session.terminal,
      textStyle: TerminalStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.terminalFont,
      ),
    );
  }
}
