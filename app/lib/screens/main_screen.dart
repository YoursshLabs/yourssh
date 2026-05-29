import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/ssh_session.dart';
import '../providers/host_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/host_detail_panel.dart';
import '../widgets/hosts_dashboard.dart';
import '../widgets/keychain_screen.dart';
import '../widgets/port_forwarding_screen.dart';
import '../widgets/settings_screen.dart';
import '../widgets/snippets_screen.dart';
import '../widgets/local_terminal_screen.dart';
import '../widgets/network_stats_overlay.dart';
import '../widgets/split_terminal_view.dart';

enum NavSection { hosts, keychain, portForwarding, webTools, snippets, localTerminal, knownHosts, settings }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  NavSection _nav = NavSection.hosts;
  bool _showHostPanel = false;
  Host? _editingHost;

  void _openHostPanel({Host? existing}) {
    setState(() {
      _showHostPanel = true;
      _editingHost = existing;
    });
  }

  void _closeHostPanel() {
    setState(() {
      _showHostPanel = false;
      _editingHost = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>().sessions;
    final activeSession = context.watch<SessionProvider>().activeSession;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          if (sessions.isNotEmpty)
            _SessionTabBar(sessions: sessions, active: activeSession),

          Expanded(
            child: Row(
              children: [
                _Sidebar(selected: _nav, onSelect: (s) => setState(() {
                  _nav = s;
                  if (s != NavSection.hosts) _closeHostPanel();
                })),
                Expanded(child: _buildContent(activeSession)),
                if (_showHostPanel && _nav == NavSection.hosts)
                  HostDetailPanel(
                    existing: _editingHost,
                    onClose: _closeHostPanel,
                    onSave: (host, password) async {
                      final hp = context.read<HostProvider>();
                      if (_editingHost != null) {
                        await hp.updateHost(host, password: password);
                      } else {
                        await hp.addHost(host, password: password);
                      }
                    },
                    onConnect: (host) => context.read<SessionProvider>().connect(host),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SshSession? active) {
    if (_nav == NavSection.hosts && active != null && active.status == SessionStatus.connected) {
      return Stack(
        children: const [
          SplitTerminalView(),
          Positioned(
            top: 8,
            right: 8,
            child: NetworkStatsOverlay(),
          ),
        ],
      );
    }
    return switch (_nav) {
      NavSection.hosts => HostsDashboard(
          onAddHost: () => _openHostPanel(),
          onEditHost: (h) => _openHostPanel(existing: h),
        ),
      NavSection.keychain => const KeychainScreen(),
      NavSection.portForwarding => const PortForwardingScreen(),
      NavSection.snippets => const SnippetsScreen(),
      NavSection.localTerminal => const LocalTerminalScreen(),
      NavSection.settings => const SettingsScreen(),
      _ => _ComingSoon(label: _nav.name),
    };
  }
}

// ── Sidebar ───────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final NavSection selected;
  final ValueChanged<NavSection> onSelect;
  const _Sidebar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: AppColors.textSecondary, size: 16),
                const SizedBox(width: 8),
                const Text('YourSSH',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),

          _navItem(Icons.dns_outlined, 'Hosts', NavSection.hosts),
          _navItem(Icons.vpn_key_outlined, 'Keychain', NavSection.keychain),
          _navItem(Icons.swap_horiz, 'Port Forwarding', NavSection.portForwarding),
          _navItem(Icons.build_outlined, 'Web Tools', NavSection.webTools),
          _navItem(Icons.code, 'Snippets', NavSection.snippets),
          _navItem(Icons.laptop_mac, 'Local Terminal', NavSection.localTerminal),
          _navItem(Icons.fact_check_outlined, 'Known Hosts', NavSection.knownHosts),

          const Spacer(),
          const Divider(height: 1, color: AppColors.border),
          _navItem(Icons.settings_outlined, 'Settings', NavSection.settings),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.purple,
                  child: const Text('Y', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('YourSSH', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                    const Text('v0.1.0', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 14, color: AppColors.textSecondary),
                  tooltip: 'New Window',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    await Process.run(Platform.resolvedExecutable, []);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, NavSection section) {
    final isSelected = selected == section;
    return _NavItem(icon: icon, label: label, selected: isSelected, onTap: () => onSelect(section));
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final iconColor = widget.selected ? AppColors.accent : AppColors.textSecondary;
    final textColor = widget.selected ? AppColors.accent : AppColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.selected ? Border.all(color: AppColors.accent.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: iconColor),
              const SizedBox(width: 10),
              Text(widget.label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: widget.selected ? FontWeight.w500 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Session Tab Bar ───────────────────────────────────────

class _SessionTabBar extends StatelessWidget {
  final List<SshSession> sessions;
  final SshSession? active;
  const _SessionTabBar({required this.sessions, required this.active});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SessionProvider>();
    return Container(
      height: 38,
      color: AppColors.sidebar,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: sessions.map((s) => _SessionTab(session: s, isActive: s.id == active?.id, provider: provider)).toList(),
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
  final SessionProvider provider;
  const _SessionTab({required this.session, required this.isActive, required this.provider});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => provider.setActive(session.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive ? Border.all(color: AppColors.border) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: session.status == SessionStatus.connected ? AppColors.accent : AppColors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(session.title, style: TextStyle(color: isActive ? AppColors.textPrimary : AppColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => provider.closeSession(session.id),
              child: const Icon(Icons.close, size: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Coming Soon Placeholder ───────────────────────────────

class _ComingSoon extends StatelessWidget {
  final String label;
  const _ComingSoon({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Coming soon', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}
