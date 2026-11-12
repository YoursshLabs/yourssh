import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/mcp_gateway_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'container_widgets.dart';
import 'devops_widgets.dart';

class McpServerScreen extends StatefulWidget {
  const McpServerScreen({super.key});

  @override
  State<McpServerScreen> createState() => _McpServerScreenState();
}

class _McpServerScreenState extends State<McpServerScreen> {
  late McpGatewayService _service;
  final _commandCtrl =
      TextEditingController(text: 'npx @anthropic-ai/mcp-server');
  final _portCtrl = TextEditingController(text: '9090');
  bool _running = false;
  int? _activePort;

  @override
  void initState() {
    super.initState();
    _service = McpGatewayService(context.read<SshService>());
  }

  @override
  void dispose() {
    _commandCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;

    if (_running) {
      await _service.stop(session.host);
      setState(() {
        _running = false;
        _activePort = null;
      });
    } else {
      final port = int.tryParse(_portCtrl.text) ?? 0;
      if (port < 1 || port > 65535) {
        AppSnack.error(context, 'Port must be between 1 and 65535');
        return;
      }
      final endpoint = McpEndpoint(
        host: session.host,
        localPort: port,
        mcpCommand: _commandCtrl.text,
      );
      final result = await _service.start(endpoint);
      if (!mounted) return;
      setState(() {
        _running = result.ok;
        _activePort = result.ok ? port : null;
      });
      if (!result.ok) {
        AppSnack.error(context, 'MCP start failed: ${result.error}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSshSession;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(YsSpace.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MCP Server Gateway',
            style: TextStyle(
              color: YsColors.foreground,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: YsSpace.s2),
          const Text(
            'Run an MCP server on your remote host and expose it locally for AI tools.',
            style: TextStyle(color: YsColors.mutedForeground, fontSize: 13),
          ),
          const SizedBox(height: YsSpace.s5),
          DevopsTextField(
            key: const ValueKey('mcp-command'),
            controller: _commandCtrl,
            label: 'MCP Server Command',
            hint: 'npx @anthropic-ai/mcp-server',
            mono: true,
          ),
          const SizedBox(height: YsSpace.s4),
          SizedBox(
            width: 160,
            child: DevopsTextField(
              key: const ValueKey('mcp-port'),
              controller: _portCtrl,
              label: 'Local Port',
              mono: true,
            ),
          ),
          const SizedBox(height: YsSpace.s5),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              key: const ValueKey('mcp-toggle'),
              variant: _running ? .destructive : .primary,
              mainAxisSize: MainAxisSize.min,
              onPress: session != null ? _toggle : null,
              prefix: Icon(_running ? FLucideIcons.square : FLucideIcons.play),
              child: Text(_running ? 'Stop MCP Server' : 'Start MCP Server'),
            ),
          ),
          const SizedBox(height: 28),
          _card(
            border: YsColors.border,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How it works',
                  style: TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: 10),
                _Tip(FLucideIcons.terminal,
                    'The MCP server command runs on your remote SSH host'),
                SizedBox(height: YsSpace.s2),
                _Tip(FLucideIcons.arrowLeftRight,
                    'A port-forward tunnel exposes it on localhost'),
                SizedBox(height: YsSpace.s2),
                _Tip(FLucideIcons.bot,
                    'Point AI tools (Claude, Cursor, etc.) to the endpoint'),
              ],
            ),
          ),
          if (_running && _activePort != null) ...[
            const SizedBox(height: YsSpace.s5),
            _card(
              border: YsColors.ok.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(FLucideIcons.circle, size: 8, color: YsColors.ok),
                      SizedBox(width: YsSpace.s2),
                      Text(
                        'MCP Server Running',
                        style: TextStyle(
                          color: YsColors.ok,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: YsSpace.s3),
                  const DevopsCaption('MCP Endpoint for AI tools:'),
                  const SizedBox(height: YsSpace.s1),
                  Row(
                    children: [
                      Flexible(
                        child: SelectableText(
                          'http://localhost:$_activePort/mcp',
                          maxLines: 1,
                          style: const TextStyle(
                            color: YsColors.accentText,
                            fontFamily: kYsMonoFontFamily,
                            fontFamilyFallback: kYsMonoFontFallback,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: YsSpace.s2),
                      ContainerIconAction(
                        icon: FLucideIcons.copy,
                        tooltip: 'Copy endpoint',
                        onPress: () => Clipboard.setData(ClipboardData(
                            text: 'http://localhost:$_activePort/mcp')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Color border, required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(YsSpace.s4),
    decoration: BoxDecoration(
      color: YsColors.card,
      borderRadius: BorderRadius.circular(YsRadius.card),
      border: Border.all(color: border),
    ),
    child: child,
  );
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: YsColors.mutedForeground),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: YsColors.mutedForeground, fontSize: 12),
        ),
      ),
    ],
  );
}
