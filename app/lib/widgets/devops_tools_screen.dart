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
    this.result,
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
  ToolResult? _result;
  bool _loading = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;

    final service = WebToolsService(context.read<SshService>());
    setState(() {
      _loading = true;
      _result = null;
    });

    final host = session.host;
    final input = _inputController.text.trim();
    final result = await switch (_selected) {
      _Tool.ping => service.ping(host, input),
      _Tool.curl => service.curl(host, input),
      _Tool.dns => service.dnsLookup(host, input),
      _Tool.traceroute => service.traceroute(host, input),
      _Tool.portScan => service.portScan(host, input),
      _Tool.whois => service.whois(host, input),
      _Tool.netstat => service.netstat(host),
      _Tool.diskUsage => service.diskUsage(host, input.isEmpty ? '/' : input),
      _Tool.topProcesses => service.topProcesses(host),
      _Tool.memory => service.memoryInfo(host),
      _Tool.httpHeaders => service.httpHeaders(host, input),
      _Tool.sslCert => service.sslCert(host, input),
    };

    setState(() {
      _result = result;
      _loading = false;
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSession;

    return Row(
      children: [
        SizedBox(
          width: 160,
          child: Material(
            color: AppColors.sidebar,
            child: ListView(
              children: _Tool.values
                  .map(
                    (tool) => ListTile(
                      leading: Icon(
                        tool.icon,
                        size: 16,
                        color: _selected == tool
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      title: Text(
                        tool.label,
                        style: TextStyle(
                          color: _selected == tool
                              ? AppColors.accent
                              : AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      selected: _selected == tool,
                      onTap: () => setState(() {
                        _selected = tool;
                        _result = null;
                      }),
                      dense: true,
                    ),
                  )
                  .toList(),
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
                      Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: AppColors.orange,
                      ),
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
                            hintStyle: const TextStyle(
                              color: AppColors.textTertiary,
                            ),
                            filled: true,
                            fillColor: AppColors.card,
                            border: const OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => session != null ? _run() : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: session != null && !_loading ? _run : null,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(_selected.label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ToolResultView(result: _result, isLoading: _loading),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
