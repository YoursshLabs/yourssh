import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tool_result.dart';
import '../providers/session_provider.dart';
import '../services/ssh_service.dart';
import '../services/web_tools_service.dart';
import '../theme/app_theme.dart';
import 'tool_result_view.dart';

String _tabLabel(String toolName, String input) {
  final raw = input.isEmpty ? toolName : '$toolName $input';
  return raw.length > 24 ? '${raw.substring(0, 21)}...' : raw;
}

class _ResultTab {
  final String id;
  final String label;
  ToolResult? result;
  bool isLoading;

  _ResultTab({
    required this.id,
    required this.label,
    this.isLoading = false,
  });
}

enum _Tool {
  ping,
  curl,
  dns,
  traceroute,
  portScan,
  whois,
  netstat,
  diskUsage,
  topProcesses,
  memory,
  httpHeaders,
  sslCert,
}

extension _ToolExt on _Tool {
  String get label => switch (this) {
    _Tool.ping => 'Ping',
    _Tool.curl => 'cURL',
    _Tool.dns => 'DNS Lookup',
    _Tool.traceroute => 'Traceroute',
    _Tool.portScan => 'Port Scan',
    _Tool.whois => 'Whois',
    _Tool.netstat => 'Netstat',
    _Tool.diskUsage => 'Disk Usage',
    _Tool.topProcesses => 'Top Processes',
    _Tool.memory => 'Memory Info',
    _Tool.httpHeaders => 'HTTP Headers',
    _Tool.sslCert => 'SSL Certificate',
  };

  IconData get icon => switch (this) {
    _Tool.ping => Icons.wifi_tethering,
    _Tool.curl => Icons.http,
    _Tool.dns => Icons.dns,
    _Tool.traceroute => Icons.route,
    _Tool.portScan => Icons.radar,
    _Tool.whois => Icons.info_outline,
    _Tool.netstat => Icons.device_hub,
    _Tool.diskUsage => Icons.storage,
    _Tool.topProcesses => Icons.memory,
    _Tool.memory => Icons.developer_board,
    _Tool.httpHeaders => Icons.receipt_long,
    _Tool.sslCert => Icons.lock_outline,
  };
}

class DevopsToolsScreen extends StatefulWidget {
  const DevopsToolsScreen({super.key});

  @override
  State<DevopsToolsScreen> createState() => _DevopsToolsScreenState();
}

class _DevopsToolsScreenState extends State<DevopsToolsScreen> {
  _Tool _selected = _Tool.ping;
  final _inputController = TextEditingController(text: '8.8.8.8');
  final List<_ResultTab> _tabs = [];
  int _activeTabIndex = -1;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;

    final service = WebToolsService(context.read<SshService>());
    final input = _inputController.text.trim();
    final label = _tabLabel(_selected.label, input);

    final tab = _ResultTab(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      isLoading: true,
    );

    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });

    final tabIndex = _activeTabIndex;
    final host = session.host;

    final result = await switch (_selected) {
      _Tool.ping        => service.ping(host, input),
      _Tool.curl        => service.curl(host, input),
      _Tool.dns         => service.dnsLookup(host, input),
      _Tool.traceroute  => service.traceroute(host, input),
      _Tool.portScan    => service.portScan(host, input),
      _Tool.whois       => service.whois(host, input),
      _Tool.netstat     => service.netstat(host),
      _Tool.diskUsage   => service.diskUsage(host, input.isEmpty ? '/' : input),
      _Tool.topProcesses => service.topProcesses(host),
      _Tool.memory      => service.memoryInfo(host),
      _Tool.httpHeaders => service.httpHeaders(host, input),
      _Tool.sslCert     => service.sslCert(host, input),
    };

    if (!mounted) return;
    setState(() {
      if (tabIndex < _tabs.length) {
        _tabs[tabIndex].result = result;
        _tabs[tabIndex].isLoading = false;
      }
    });
  }

  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _clearAllTabs() {
    setState(() {
      _tabs.clear();
      _activeTabIndex = -1;
    });
  }

  bool get _needsInput => switch (_selected) {
    _Tool.netstat || _Tool.topProcesses || _Tool.memory => false,
    _ => true,
  };

  String get _inputHint => switch (_selected) {
    _Tool.ping ||
    _Tool.dns ||
    _Tool.traceroute ||
    _Tool.whois ||
    _Tool.portScan => 'Hostname or IP (e.g. 8.8.8.8)',
    _Tool.curl || _Tool.httpHeaders => 'URL (e.g. https://example.com)',
    _Tool.sslCert => 'Hostname (e.g. example.com)',
    _Tool.diskUsage => 'Path (e.g. /)',
    _ => '',
  };

  Widget _buildTabBar() {
    if (_tabs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 33,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _tabs.asMap().entries.map((e) {
            final i = e.key;
            final tab = e.value;
            final isActive = i == _activeTabIndex;

            return GestureDetector(
              onTap: () => setState(() => _activeTabIndex = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.bg : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppColors.accent : Colors.transparent,
                      width: 2,
                    ),
                    right: const BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.isLoading)
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: AppColors.accent),
                      )
                    else
                      Icon(
                        tab.result?.isSuccess == true
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 11,
                        color: tab.result?.isSuccess == true
                            ? AppColors.accent
                            : AppColors.red,
                      ),
                    const SizedBox(width: 6),
                    Text(
                      tab.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                        fontWeight: isActive
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _closeTab(i),
                      child: const Icon(Icons.close,
                          size: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _navItem(_Tool tool) => _NavItem(
        icon: tool.icon,
        label: tool.label,
        active: _selected == tool,
        onTap: () => setState(() => _selected = tool),
      );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSession;

    return Row(
      children: [
        SizedBox(
          width: 160,
          child: Container(
            color: AppColors.sidebar,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView(
              children: [
                const _SidebarSection('Network'),
                ...[
                  _Tool.ping, _Tool.curl, _Tool.dns,
                  _Tool.traceroute, _Tool.portScan, _Tool.whois, _Tool.netstat,
                ].map(_navItem),
                const _SidebarSection('System'),
                ...[_Tool.diskUsage, _Tool.topProcesses, _Tool.memory]
                    .map(_navItem),
                const _SidebarSection('HTTP'),
                ...[_Tool.httpHeaders, _Tool.sslCert].map(_navItem),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: Column(
            children: [
              if (session == null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: AppColors.card,
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
                      SizedBox(width: 8),
                      Text(
                        'No active session — connect to a host first',
                        style: TextStyle(color: AppColors.orange, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (_needsInput) ...[
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: _inputHint,
                            hintStyle: const TextStyle(color: AppColors.textTertiary),
                            filled: true,
                            fillColor: AppColors.card,
                            border: const OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => session != null ? _run() : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: session != null ? _run : null,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(_selected.label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    if (_tabs.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear_all,
                            size: 18, color: AppColors.textSecondary),
                        tooltip: 'Clear all tabs',
                        onPressed: _clearAllTabs,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _buildTabBar(),
              Expanded(
                child: _activeTabIndex >= 0 && _activeTabIndex < _tabs.length
                    ? ToolResultView(
                        result: _tabs[_activeTabIndex].result,
                        isLoading: _tabs[_activeTabIndex].isLoading,
                      )
                    : const ToolResultView(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Sidebar widgets ────────────────────────────────────────

class _SidebarSection extends StatelessWidget {
  final String label;
  const _SidebarSection(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final color = widget.active ? AppColors.accent : AppColors.textSecondary;

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
            border: widget.active
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight:
                        widget.active ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
