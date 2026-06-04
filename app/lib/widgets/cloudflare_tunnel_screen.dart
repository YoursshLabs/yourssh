import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tunnel_config.dart';
import '../providers/session_provider.dart';
import '../providers/tunnel_provider.dart';
import '../services/cloudflare_tunnel_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

class CloudflareTunnelScreen extends StatelessWidget {
  const CloudflareTunnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TunnelProvider()..load(),
      child: const _CloudflareTunnelBody(),
    );
  }
}

class _CloudflareTunnelBody extends StatefulWidget {
  const _CloudflareTunnelBody();

  @override
  State<_CloudflareTunnelBody> createState() => _CloudflareTunnelBodyState();
}

class _CloudflareTunnelBodyState extends State<_CloudflareTunnelBody> {
  bool _showPanel = false;

  Future<void> _stopTunnel(TunnelConfig tunnel) async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;

    final provider = context.read<TunnelProvider>();
    final service = CloudflareTunnelService(context.read<SshService>());

    provider.updateStatus(tunnel.id, TunnelStatus.starting);
    await service.stopTunnel(session.host, tunnel.localPort);
    provider.resetToIdle(tunnel.id);
  }

  Future<void> _startTunnel(TunnelConfig tunnel) async {
    final session = context.read<SessionProvider>().activeSshSession;
    if (session == null) return;

    final provider = context.read<TunnelProvider>();
    final service = CloudflareTunnelService(context.read<SshService>());

    provider.updateStatus(tunnel.id, TunnelStatus.starting);

    final installed = await service.isCloudflaredInstalled(session.host);
    if (!installed) {
      provider.updateStatus(tunnel.id, TunnelStatus.error,
          error:
              'cloudflared not found on server. Install with: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared');
      return;
    }

    final result =
        await service.startQuickTunnel(session.host, tunnel.localPort);
    if (result.ok) {
      provider.updateStatus(tunnel.id, TunnelStatus.active, url: result.url);
    } else {
      provider.updateStatus(tunnel.id, TunnelStatus.error, error: result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final session = context.watch<SessionProvider>().activeSshSession;

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text('Cloudflare Tunnels',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _showPanel = true),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Tunnel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              if (session == null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Connect to a host to manage tunnels',
                      style: TextStyle(
                          color: AppColors.orange, fontSize: 12)),
                ),
              Expanded(
                child: provider.tunnels.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_outlined,
                                size: 40, color: AppColors.textTertiary),
                            const SizedBox(height: 12),
                            const Text('No tunnels yet',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14)),
                            const SizedBox(height: 6),
                            const Text(
                              'Add a tunnel to expose a local port via Cloudflare.',
                              style: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            if (session == null)
                              const Text('Connect to a host first.',
                                  style: TextStyle(
                                      color: AppColors.orange, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: provider.tunnels.length,
                        itemBuilder: (_, i) => _buildTunnelTile(
                            provider.tunnels[i], session != null),
                      ),
              ),
            ],
          ),
        ),
        if (_showPanel)
          _TunnelPanel(
            onClose: () => setState(() => _showPanel = false),
            onSave: (config) {
              context.read<TunnelProvider>().add(config);
              setState(() => _showPanel = false);
            },
          ),
      ],
    );
  }

  Widget _buildTunnelTile(TunnelConfig tunnel, bool hasSession) {
    final statusColor = switch (tunnel.status) {
      TunnelStatus.idle => AppColors.textTertiary,
      TunnelStatus.starting => AppColors.orange,
      TunnelStatus.active => AppColors.accent,
      TunnelStatus.error => AppColors.red,
    };

    return ListTile(
      leading: Icon(Icons.cloud_queue, color: statusColor),
      title: Text(tunnel.label,
          style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: tunnel.publicUrl != null
          ? GestureDetector(
              onTap: () => launchUrl(Uri.parse(tunnel.publicUrl!)),
              child: Text(tunnel.publicUrl!,
                  style: const TextStyle(
                      color: AppColors.blue, fontSize: 12)),
            )
          : tunnel.errorMessage != null
              ? Text(tunnel.errorMessage!,
                  style: const TextStyle(
                      color: AppColors.red, fontSize: 11))
              : Text('Port: ${tunnel.localPort}',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tunnel.publicUrl != null)
            IconButton(
              icon: const Icon(Icons.copy,
                  size: 16, color: AppColors.textSecondary),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: tunnel.publicUrl!)),
              tooltip: 'Copy URL',
            ),
          if (tunnel.status == TunnelStatus.idle ||
              tunnel.status == TunnelStatus.error)
            IconButton(
              icon: const Icon(Icons.play_arrow,
                  size: 16, color: AppColors.accent),
              onPressed: hasSession ? () => _startTunnel(tunnel) : null,
              tooltip: 'Start tunnel',
            ),
          if (tunnel.status == TunnelStatus.active)
            IconButton(
              icon: const Icon(Icons.stop, size: 16, color: AppColors.red),
              onPressed: hasSession ? () => _stopTunnel(tunnel) : null,
              tooltip: 'Stop tunnel',
            ),
          if (tunnel.status == TunnelStatus.starting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.orange),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.textTertiary),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.sidebar,
                  title: const Text('Remove tunnel',
                      style: TextStyle(color: AppColors.textPrimary)),
                  content: Text('Remove "${tunnel.label}"?',
                      style: const TextStyle(
                          color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.red),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && mounted) {
                context.read<TunnelProvider>().remove(tunnel.id);
              }
            },
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

// ── Tunnel Panel ──────────────────────────────────────────

class _TunnelPanel extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(TunnelConfig) onSave;
  const _TunnelPanel({required this.onClose, required this.onSave});

  @override
  State<_TunnelPanel> createState() => _TunnelPanelState();
}

class _TunnelPanelState extends State<_TunnelPanel> {
  final _labelCtrl = TextEditingController(text: 'My Service');
  final _portCtrl = TextEditingController(text: '3000');

  @override
  void dispose() {
    _labelCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text) ?? 3000;
    if (label.isEmpty) return;
    widget.onSave(TunnelConfig(
      label: label,
      type: TunnelType.cloudflare,
      localPort: port,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _field(_labelCtrl, 'Label', autofocus: true),
                const SizedBox(height: 12),
                _field(_portCtrl, 'Local Port',
                    keyboardType: TextInputType.number),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black),
                    child: const Text('Add Tunnel',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text('New Cloudflare Tunnel',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool autofocus = false,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      autofocus: autofocus,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.accent)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
