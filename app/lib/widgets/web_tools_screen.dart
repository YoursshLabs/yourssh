import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'web_tools/embedded_browser.dart';
import 'web_tools/http_client.dart';
import 'web_tools/utility_tools.dart';
import 'web_tools/port_forward_browser.dart';

enum _WebTool { browser, http, utilities, portForward }

class WebToolsScreen extends StatefulWidget {
  const WebToolsScreen({super.key});

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
    return Row(
      children: [
        _SubNav(active: _active, onSelect: (t) => setState(() => _active = t)),
        Container(width: 1, color: AppColors.border),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() => switch (_active) {
        _WebTool.browser     => EmbeddedBrowser(key: ValueKey(_browserUrl), initialUrl: _browserUrl),
        _WebTool.http        => const HttpClientTool(),
        _WebTool.utilities   => const UtilityTools(),
        _WebTool.portForward => PortForwardBrowser(onOpenUrl: _openUrl),
      };
}

class _SubNav extends StatelessWidget {
  final _WebTool active;
  final ValueChanged<_WebTool> onSelect;

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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Web Tools',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _item(Icons.language, 'Browser', _WebTool.browser),
          _item(Icons.http, 'HTTP Client', _WebTool.http),
          _item(Icons.build_circle_outlined, 'Utilities', _WebTool.utilities),
          _item(Icons.router_outlined, 'Port Tunnels', _WebTool.portForward),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, _WebTool tool) {
    final sel = active == tool;
    return _SubNavItem(icon: icon, label: label, selected: sel, onTap: () => onSelect(tool));
  }
}

class _SubNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubNavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  State<_SubNavItem> createState() => _SubNavItemState();
}

class _SubNavItemState extends State<_SubNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;

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
              Icon(widget.icon, size: 14,
                  color: widget.selected ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: TextStyle(
                    color: widget.selected ? AppColors.accent : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: widget.selected ? FontWeight.w500 : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
