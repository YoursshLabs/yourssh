import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../web_tools_plugin_config.dart';
import 'embedded_browser.dart';
import 'http_client.dart';
import 'utility_tools.dart';

enum _WebTool { browser, http, utilities, portForward }

class WebToolsScreen extends StatefulWidget {
  final WebToolsPluginConfig config;

  const WebToolsScreen({super.key, required this.config});

  @override
  State<WebToolsScreen> createState() => _WebToolsScreenState();
}

class _WebToolsScreenState extends State<WebToolsScreen> {
  _WebTool _active = _WebTool.browser;
  String? _browserUrl;

  void _openUrl(String url) {
    setState(() {
      _browserUrl = url;
      _active = _WebTool.browser;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: Row(
        children: [
          _SubNav(active: _active, onSelect: (t) => setState(() => _active = t)),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() => switch (_active) {
        _WebTool.browser     => EmbeddedBrowser(key: ValueKey(_browserUrl), initialUrl: _browserUrl),
        _WebTool.http        => const HttpClientTool(),
        _WebTool.utilities   => const UtilityTools(),
        _WebTool.portForward => widget.config.portForwardBrowserBuilder(_openUrl),
      };
}

class _SubNav extends StatelessWidget {
  final _WebTool active;
  final ValueChanged<_WebTool> onSelect;

  const _SubNav({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      child: FSidebar(
        header: const Padding(
          padding: EdgeInsets.fromLTRB(YsSpace.s4, YsSpace.s4, YsSpace.s4, 0),
          child: Text(
            'Web Tools',
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
              _item(FLucideIcons.globe, 'Browser', _WebTool.browser),
              _item(FLucideIcons.globe, 'HTTP Client', _WebTool.http),
              _item(FLucideIcons.wrench, 'Utilities', _WebTool.utilities),
              _item(FLucideIcons.router, 'Port Tunnels', _WebTool.portForward),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, _WebTool tool) => FSidebarItem(
        key: ValueKey('web-tools-nav-${tool.name}'),
        icon: Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: active == tool,
        onPress: () => onSelect(tool),
      );
}
