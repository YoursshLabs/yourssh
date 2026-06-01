import 'package:flutter/material.dart';
import '../devops_plugin_config.dart';
import '../theme.dart';
import 's3_browser_screen.dart';
import 'lan_share_screen.dart';

enum _DevOpsTool { containers, networkTools, cloudflare, lanShare, mailCatcher, mcpServer, s3Browser }

class DevOpsHubScreen extends StatefulWidget {
  final DevOpsPluginConfig config;
  const DevOpsHubScreen({super.key, required this.config});

  @override
  State<DevOpsHubScreen> createState() => _DevOpsHubScreenState();
}

class _DevOpsHubScreenState extends State<DevOpsHubScreen> {
  _DevOpsTool _active = _DevOpsTool.networkTools;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SubNav(active: _active, onSelect: (t) => setState(() => _active = t)),
        Container(width: 1, color: DevOpsColors.border),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() => switch (_active) {
        _DevOpsTool.containers  => widget.config.containersScreen,
        _DevOpsTool.networkTools => widget.config.networkToolsScreen,
        _DevOpsTool.cloudflare  => widget.config.cloudflareScreen,
        _DevOpsTool.lanShare    => const LanShareScreen(),
        _DevOpsTool.mailCatcher => widget.config.mailCatcherScreen,
        _DevOpsTool.mcpServer   => widget.config.mcpServerScreen,
        _DevOpsTool.s3Browser   => const S3BrowserScreen(),
      };
}

class _SubNav extends StatelessWidget {
  final _DevOpsTool active;
  final ValueChanged<_DevOpsTool> onSelect;

  const _SubNav({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      color: DevOpsColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'DevOps',
              style: const TextStyle(
                color: DevOpsColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _item(_DevOpsTool.containers, Icons.widgets_outlined, 'Containers'),
          _item(_DevOpsTool.networkTools, Icons.network_check, 'Network Tools'),
          _item(_DevOpsTool.cloudflare, Icons.cloud_outlined, 'Cloudflare'),
          _item(_DevOpsTool.lanShare, Icons.share_outlined, 'LAN Share'),
          _item(_DevOpsTool.mailCatcher, Icons.email_outlined, 'Mail Catcher'),
          _item(_DevOpsTool.mcpServer, Icons.hub_outlined, 'MCP Server'),
          _item(_DevOpsTool.s3Browser, Icons.storage_outlined, 'S3 Browser'),
        ],
      ),
    );
  }

  Widget _item(_DevOpsTool tool, IconData icon, String label) {
    final isActive = active == tool;
    return InkWell(
      onTap: () => onSelect(tool),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? DevOpsColors.accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? DevOpsColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: isActive ? DevOpsColors.accent : DevOpsColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? DevOpsColors.accent : DevOpsColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
