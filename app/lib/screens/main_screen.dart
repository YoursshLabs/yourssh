import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/known_host.dart';
import '../models/ssh_session.dart';
import '../providers/host_provider.dart';
import '../providers/known_hosts_provider.dart';
import '../providers/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/host_detail_panel.dart';
import '../widgets/hosts_dashboard.dart';
import '../widgets/keychain_screen.dart';
import '../widgets/known_hosts_screen.dart';
import '../widgets/port_forwarding_screen.dart';
import '../widgets/settings_screen.dart';
import '../widgets/snippets_screen.dart';
import '../widgets/local_terminal_screen.dart';
import '../widgets/network_stats_overlay.dart';
import '../widgets/dual_panel_sftp_screen.dart';
import '../widgets/split_terminal_view.dart';
import '../widgets/web_tools_screen.dart';

enum NavSection { hosts, keychain, portForwarding, sftp, webTools, snippets, localTerminal, knownHosts, settings }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  NavSection _nav = NavSection.hosts;
  bool _showHostPanel = false;
  Host? _editingHost;
  String? _initialGroup;
  bool _viewingTerminal = false;
  final _sftpConnectionNotifier = ValueNotifier<bool>(false);
  SessionProvider? _sessionProvider;
  KnownHostsProvider? _knownHostsProvider;
  bool _hostKeyDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _sftpConnectionNotifier.addListener(_onSftpConnectionChanged);
  }

  void _onSftpConnectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<SessionProvider>();
    if (_sessionProvider != provider) {
      _sessionProvider?.removeListener(_onSessionsChanged);
      _sessionProvider = provider;
      provider.addListener(_onSessionsChanged);
    }
    final knownHostsProvider = context.read<KnownHostsProvider>();
    if (_knownHostsProvider != knownHostsProvider) {
      _knownHostsProvider?.removeListener(_onKnownHostsChanged);
      _knownHostsProvider = knownHostsProvider;
      knownHostsProvider.addListener(_onKnownHostsChanged);
    }
  }

  void _onKnownHostsChanged() {
    final challenge = _knownHostsProvider?.pendingChallenge;
    if (challenge != null && !_hostKeyDialogShowing && mounted) {
      _hostKeyDialogShowing = true;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HostKeyDialog(challenge: challenge),
      ).then((trusted) {
        challenge.resolve(trusted ?? false);
        _hostKeyDialogShowing = false;
      });
    }
  }

  void _onSessionsChanged() {
    if (!mounted) return;
    final sessions = _sessionProvider?.sessions ?? [];
    if (sessions.isNotEmpty && !_viewingTerminal) {
      setState(() => _viewingTerminal = true);
    } else if (sessions.isEmpty && _viewingTerminal) {
      setState(() => _viewingTerminal = false);
    }
  }

  @override
  void dispose() {
    _sftpConnectionNotifier.removeListener(_onSftpConnectionChanged);
    _sftpConnectionNotifier.dispose();
    _sessionProvider?.removeListener(_onSessionsChanged);
    _knownHostsProvider?.removeListener(_onKnownHostsChanged);
    super.dispose();
  }

  void _openHostPanel({Host? existing, String? initialGroup}) {
    setState(() {
      _showHostPanel = true;
      _editingHost = existing;
      _initialGroup = initialGroup;
    });
  }

  void _closeHostPanel() {
    setState(() {
      _showHostPanel = false;
      _editingHost = null;
      _initialGroup = null;
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
          _TopTabBar(
            sessions: sessions,
            active: activeSession,
            nav: _nav,
            viewingTerminal: _viewingTerminal && sessions.isNotEmpty,
            onNavSelect: (s) => setState(() {
              _nav = s;
              _viewingTerminal = false;
              if (s != NavSection.hosts) _closeHostPanel();
              if (s != NavSection.sftp) _sftpConnectionNotifier.value = false;
            }),
            onSessionTap: (_) => setState(() => _viewingTerminal = true),
            onAddSession: () => _openHostPanel(),
          ),

          Expanded(
            child: Row(
              children: [
                if ((!_viewingTerminal || sessions.isEmpty) &&
                    !(_nav == NavSection.sftp && _sftpConnectionNotifier.value))
                  _Sidebar(selected: _nav, onSelect: (s) => setState(() {
                    _nav = s;
                    _viewingTerminal = false;
                    if (s != NavSection.hosts) _closeHostPanel();
                    if (s != NavSection.sftp) _sftpConnectionNotifier.value = false;
                  })),
                Expanded(child: _buildContent(activeSession)),
                if (_showHostPanel && _nav == NavSection.hosts && !_viewingTerminal)
                  HostDetailPanel(
                    existing: _editingHost,
                    initialGroup: _initialGroup,
                    onClose: _closeHostPanel,
                    onSave: (host, password) async {
                      final hp = context.read<HostProvider>();
                      if (_editingHost != null) {
                        await hp.updateHost(host, password: password);
                      } else {
                        await hp.addHost(host, password: password);
                      }
                    },
                    onConnect: (host) async {
                      setState(() => _viewingTerminal = true);
                      await context.read<SessionProvider>().connect(host);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SshSession? active) {
    if (_viewingTerminal && active != null) {
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
          onOpenLocalTerminal: () => setState(() => _nav = NavSection.localTerminal),
          onNewGroup: (group) => _openHostPanel(initialGroup: group),
        ),
      NavSection.keychain => const KeychainScreen(),
      NavSection.portForwarding => const PortForwardingScreen(),
      NavSection.sftp => DualPanelSftpScreen(
          connectionNotifier: _sftpConnectionNotifier,
        ),
      NavSection.snippets => const SnippetsScreen(),
      NavSection.localTerminal => const LocalTerminalScreen(),
      NavSection.knownHosts => const KnownHostsScreen(),
      NavSection.settings => const SettingsScreen(),
      NavSection.webTools => const WebToolsScreen(),
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
          _navItem(Icons.folder_open, 'SFTP', NavSection.sftp),
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

// ── Top Tab Bar ───────────────────────────────────────────

class _TopTabBar extends StatelessWidget {
  final List<SshSession> sessions;
  final SshSession? active;
  final NavSection nav;
  final bool viewingTerminal;
  final ValueChanged<NavSection> onNavSelect;
  final ValueChanged<String> onSessionTap;
  final VoidCallback onAddSession;

  const _TopTabBar({
    required this.sessions,
    required this.active,
    required this.nav,
    required this.viewingTerminal,
    required this.onNavSelect,
    required this.onSessionTap,
    required this.onAddSession,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SessionProvider>();
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        children: [
          // Pinned nav shortcuts
          _PinnedTab(
            icon: Icons.home_outlined,
            label: 'Home',
            active: nav == NavSection.hosts && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.hosts),
          ),
          _PinnedTab(
            icon: Icons.folder_outlined,
            label: 'SFTP',
            active: nav == NavSection.sftp && !viewingTerminal,
            onTap: () => onNavSelect(NavSection.sftp),
          ),
          // Divider
          Container(width: 1, height: 18, color: const Color(0xFF2A2A2A)),
          const SizedBox(width: 4),
          // Session tabs (scrollable)
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: sessions
                  .map((s) => _SessionTab(
                        session: s,
                        isActive: s.id == active?.id && viewingTerminal,
                        provider: provider,
                        onTap: () => onSessionTap(s.id),
                      ))
                  .toList(),
            ),
          ),
          // "+" button
          _AddTabBtn(onTap: onAddSession),
        ],
      ),
    );
  }
}

class _PinnedTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PinnedTab({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  State<_PinnedTab> createState() => _PinnedTabState();
}

class _PinnedTabState extends State<_PinnedTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? AppColors.accent
        : _hovered
            ? const Color(0xFFAAAAAA)
            : const Color(0xFF666666);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: widget.active
                ? const Border(bottom: BorderSide(color: AppColors.accent, width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: widget.active ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTab extends StatefulWidget {
  final SshSession session;
  final bool isActive;
  final SessionProvider provider;
  final VoidCallback onTap;
  const _SessionTab({required this.session, required this.isActive, required this.provider, required this.onTap});

  @override
  State<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends State<_SessionTab> {
  bool _hovered = false;

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
              // X close button (left, per image)
              GestureDetector(
                onTap: () => widget.provider.closeSession(widget.session.id),
                child: Icon(
                  Icons.close,
                  size: 11,
                  color: _hovered || widget.isActive ? const Color(0xFF888888) : const Color(0xFF444444),
                ),
              ),
              const SizedBox(width: 8),
              // Host label
              Text(
                widget.session.host.label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 12,
                  fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              // Terminal icon (right, per image)
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

class _AddTabBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _AddTabBtn({required this.onTap});

  @override
  State<_AddTabBtn> createState() => _AddTabBtnState();
}

class _AddTabBtnState extends State<_AddTabBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36,
          height: 38,
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 16,
            color: _hovered ? const Color(0xFFAAAAAA) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

// ── Host Key Mismatch Dialog ──────────────────────────────

class _HostKeyDialog extends StatelessWidget {
  final HostKeyChallenge challenge;
  const _HostKeyDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('Host key changed',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${challenge.host}:${challenge.port}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          _FpRow(label: 'Old', fp: challenge.oldFingerprint),
          const SizedBox(height: 4),
          _FpRow(label: 'New', fp: challenge.newFingerprint),
          const SizedBox(height: 12),
          const Text(
            'This could indicate a man-in-the-middle attack. '
            'Only trust the new key if you know the server key changed.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
          child: const Text('Trust new key'),
        ),
      ],
    );
  }
}

class _FpRow extends StatelessWidget {
  final String label;
  final String fp;
  const _FpRow({required this.label, required this.fp});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text('$label:',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: Text(fp,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}
