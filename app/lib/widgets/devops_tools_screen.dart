import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tool_result.dart';
import '../providers/session_provider.dart';
import '../services/ssh_service.dart';
import '../services/web_tools_service.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'container_widgets.dart';
import 'devops_widgets.dart';
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
    _Tool.ping => FLucideIcons.radio,
    _Tool.curl => FLucideIcons.globe,
    _Tool.dns => FLucideIcons.server,
    _Tool.traceroute => FLucideIcons.route,
    _Tool.portScan => FLucideIcons.radar,
    _Tool.whois => FLucideIcons.info,
    _Tool.netstat => FLucideIcons.network,
    _Tool.diskUsage => FLucideIcons.hardDrive,
    _Tool.topProcesses => FLucideIcons.cpu,
    _Tool.memory => FLucideIcons.memoryStick,
    _Tool.httpHeaders => FLucideIcons.receipt,
    _Tool.sslCert => FLucideIcons.lock,
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

  IconData _iconFor(_Tool tool) => switch (tool) {
    _Tool.ping || _Tool.traceroute => FLucideIcons.radio,
    _Tool.dns => FLucideIcons.server,
    _Tool.portScan => FLucideIcons.radar,
    _Tool.whois => FLucideIcons.info,
    _Tool.curl || _Tool.httpHeaders => FLucideIcons.link,
    _Tool.sslCert => FLucideIcons.lock,
    _Tool.diskUsage => FLucideIcons.folder,
    _ => FLucideIcons.search,
  };

  String _defaultInputFor(_Tool tool) => switch (tool) {
    _Tool.ping || _Tool.dns || _Tool.traceroute || _Tool.portScan => '8.8.8.8',
    _Tool.curl || _Tool.httpHeaders => 'https://example.com',
    _Tool.sslCert || _Tool.whois => 'example.com',
    _Tool.diskUsage => '/',
    _ => '',
  };

  void _selectTool(_Tool tool) {
    setState(() {
      _selected = tool;
      _inputController.text = _defaultInputFor(tool);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final session = context.read<SessionProvider>().activeSshSession;
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
      height: YsTab.height,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (i, tab) in _tabs.indexed)
              YsTab(
                key: ValueKey('devops-tab-${tab.id}'),
                active: i == _activeTabIndex,
                onTap: () => setState(() => _activeTabIndex = i),
                onClose: () => _closeTab(i),
                closeTooltip: 'Close tab',
                leading: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: tab.isLoading
                      ? const ContainerSpinner(size: 11)
                      : Icon(
                          tab.result?.isSuccess == true
                              ? FLucideIcons.circleCheck
                              : FLucideIcons.circleAlert,
                          size: 11,
                          color: tab.result?.isSuccess == true
                              ? YsColors.ok
                              : YsColors.error,
                        ),
                ),
                label: Text(tab.label, maxLines: 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(_Tool tool) => _NavItem(
        icon: tool.icon,
        label: tool.label,
        active: _selected == tool,
        onTap: () => _selectTool(tool),
      );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSshSession;

    return Row(
      children: [
        Container(
          width: 160,
          color: YsColors.sidebar,
          padding: const EdgeInsets.symmetric(vertical: YsSpace.s2),
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
        const VerticalDivider(width: 1, color: YsColors.border),
        Expanded(
          child: Column(
            children: [
              if (session == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(YsSpace.s2),
                  color: YsColors.card,
                  child: const Row(
                    children: [
                      Icon(FLucideIcons.triangleAlert,
                          size: 14, color: YsColors.warn),
                      SizedBox(width: YsSpace.s2),
                      Expanded(
                        child: Text(
                          'No active session — connect to a host first',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: YsColors.warn, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(YsSpace.s3),
                child: Row(
                  children: [
                    if (_needsInput) ...[
                      Expanded(
                        child: DevopsTextField(
                          key: const ValueKey('devops-input'),
                          controller: _inputController,
                          hint: _inputHint,
                          icon: _iconFor(_selected),
                          mono: true,
                          onSubmit: () {
                            if (session != null) _run();
                          },
                        ),
                      ),
                      const SizedBox(width: YsSpace.s2),
                    ],
                    FButton(
                      key: const ValueKey('devops-run'),
                      mainAxisSize: MainAxisSize.min,
                      onPress: session != null ? _run : null,
                      prefix: const Icon(FLucideIcons.play),
                      child: Text(_selected.label),
                    ),
                    if (_tabs.isNotEmpty) ...[
                      const SizedBox(width: YsSpace.s2),
                      ContainerIconAction(
                        icon: FLucideIcons.listX,
                        tooltip: 'Clear all tabs',
                        onPress: _clearAllTabs,
                      ),
                    ],
                  ],
                ),
              ),
              const FDivider(style: .delta(padding: .value(EdgeInsets.zero))),
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
        color: YsColors.mutedForeground,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
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
  Widget build(BuildContext context) => FTappable(
    semanticsLabel: label,
    selected: active,
    onPress: onTap,
    builder: (context, variants, child) {
      final hovered = variants.contains(FTappableVariant.hovered);
      final focused = variants.contains(FTappableVariant.focused);
      final color = active ? YsColors.primary : YsColors.mutedForeground;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? YsColors.primary.withValues(alpha: 0.12)
              : hovered
              ? YsColors.secondary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(YsRadius.control),
          border: active || focused
              ? Border.all(
                  color: YsColors.primary.withValues(alpha: focused ? 1 : 0.2),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: YsSpace.s2),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
