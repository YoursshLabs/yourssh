import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'cloudflare_tunnel_screen.dart';
import 'devops_tools_screen.dart';
import 'lan_share_screen.dart';
import 'mail_catcher_screen.dart';
import 'mcp_server_screen.dart';
import 's3_browser_screen.dart';

enum _DevOpsTool { networkTools, cloudflare, lanShare, mailCatcher, mcpServer, s3Browser }

class DevOpsHubScreen extends StatefulWidget {
  const DevOpsHubScreen({super.key});

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
        Container(width: 1, color: AppColors.border),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() => switch (_active) {
        _DevOpsTool.networkTools => const DevopsToolsScreen(),
        _DevOpsTool.cloudflare  => const CloudflareTunnelScreen(),
        _DevOpsTool.lanShare    => const LanShareScreen(),
        _DevOpsTool.mailCatcher => const MailCatcherScreen(),
        _DevOpsTool.mcpServer   => const McpServerScreen(),
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
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'DevOps',
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
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
    return _SubNavItem(
      icon: icon,
      label: label,
      active: isActive,
      onTap: () => onSelect(tool),
    );
  }
}

class _SubNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SubNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_SubNavItem> createState() => _SubNavItemState();
}

class _SubNavItemState extends State<_SubNavItem> {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.active
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: widget.active ? FontWeight.w500 : FontWeight.normal,
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
