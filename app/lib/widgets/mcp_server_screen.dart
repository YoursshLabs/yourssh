import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/mcp_gateway_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Port must be between 1 and 65535'),
            backgroundColor: AppColors.red,
          ),
        );
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MCP Server Gateway',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Run an MCP server on your remote host and expose it locally for AI tools.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _label('MCP Server Command'),
          const SizedBox(height: 6),
          TextField(
            controller: _commandCtrl,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'npx @anthropic-ai/mcp-server',
              hintStyle: TextStyle(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border)),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 16),
          _label('Local Port'),
          const SizedBox(height: 6),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _portCtrl,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 13),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: session != null ? _toggle : null,
            icon: Icon(_running ? Icons.stop : Icons.play_arrow, size: 16),
            label: Text(_running ? 'Stop MCP Server' : 'Start MCP Server'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _running ? AppColors.red : AppColors.accent,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How it works',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4)),
                const SizedBox(height: 10),
                _tip(Icons.terminal_outlined,
                    'The MCP server command runs on your remote SSH host'),
                const SizedBox(height: 8),
                _tip(Icons.swap_horiz_outlined,
                    'A port-forward tunnel exposes it on localhost'),
                const SizedBox(height: 8),
                _tip(Icons.smart_toy_outlined,
                    'Point AI tools (Claude, Cursor, etc.) to the endpoint'),
              ],
            ),
          ),
          if (_running && _activePort != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text('MCP Server Running',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _label('MCP Endpoint for AI tools:'),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SelectableText(
                        'http://localhost:$_activePort/mcp',
                        style: const TextStyle(
                            color: AppColors.blue,
                            fontFamily: 'monospace',
                            fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy,
                            size: 14, color: AppColors.textSecondary),
                        onPressed: () => Clipboard.setData(ClipboardData(
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

  Widget _label(String text) =>
      Text(text,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12));

  Widget _tip(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
      ],
    );
  }
}
