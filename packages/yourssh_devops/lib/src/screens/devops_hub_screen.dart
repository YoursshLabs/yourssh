import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../devops_plugin_config.dart';
import 's3_browser_screen.dart';
import 'lan_share_screen.dart';

enum _DevOpsTool {
  containers,
  networkTools,
  cloudflare,
  lanShare,
  mailCatcher,
  mcpServer,
  s3Browser,
}

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
    return ColoredBox(
      color: YsColors.background,
      child: Row(
        children: [
          _SubNav(
            active: _active,
            onSelect: (t) => setState(() => _active = t),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() => switch (_active) {
    _DevOpsTool.containers => widget.config.containersScreen,
    _DevOpsTool.networkTools => widget.config.networkToolsScreen,
    _DevOpsTool.cloudflare => widget.config.cloudflareScreen,
    _DevOpsTool.lanShare => const LanShareScreen(),
    _DevOpsTool.mailCatcher => widget.config.mailCatcherScreen,
    _DevOpsTool.mcpServer => widget.config.mcpServerScreen,
    _DevOpsTool.s3Browser => const S3BrowserScreen(),
  };
}

class _SubNav extends StatelessWidget {
  final _DevOpsTool active;
  final ValueChanged<_DevOpsTool> onSelect;

  const _SubNav({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      child: FSidebar(
        header: const Padding(
          padding: EdgeInsets.fromLTRB(YsSpace.s4, YsSpace.s4, YsSpace.s4, 0),
          child: Text(
            'DevOps',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: YsColors.mutedForeground,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        children: [
          FSidebarGroup(
            children: [
              _item(
                _DevOpsTool.containers,
                FLucideIcons.container,
                'Containers',
              ),
              _item(
                _DevOpsTool.networkTools,
                FLucideIcons.activity,
                'Network Tools',
              ),
              _item(_DevOpsTool.cloudflare, FLucideIcons.cloud, 'Cloudflare'),
              _item(_DevOpsTool.lanShare, FLucideIcons.share2, 'LAN Share'),
              _item(_DevOpsTool.mailCatcher, FLucideIcons.mail, 'Mail Catcher'),
              _item(_DevOpsTool.mcpServer, FLucideIcons.network, 'MCP Server'),
              _item(_DevOpsTool.s3Browser, FLucideIcons.database, 'S3 Browser'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(_DevOpsTool tool, IconData icon, String label) {
    return FSidebarItem(
      key: ValueKey('devops-nav-${tool.name}'),
      icon: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: active == tool,
      onPress: () => onSelect(tool),
    );
  }
}
