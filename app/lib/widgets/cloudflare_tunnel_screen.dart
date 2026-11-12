import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tunnel_config.dart';
import '../providers/session_provider.dart';
import '../providers/tunnel_provider.dart';
import '../services/cloudflare_tunnel_service.dart';
import '../services/ssh_service.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'container_widgets.dart';
import 'devops_widgets.dart';

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(YsSpace.s3),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cloudflare Tunnels',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: YsColors.foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FButton(
                      key: const ValueKey('tunnel-new'),
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => setState(() => _showPanel = true),
                      prefix: const Icon(FLucideIcons.plus),
                      child: const Text('New Tunnel'),
                    ),
                  ],
                ),
              ),
              if (session == null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: YsSpace.s3),
                  child: Text(
                    'Connect to a host to manage tunnels',
                    style: TextStyle(color: YsColors.warn, fontSize: 12),
                  ),
                ),
              Expanded(
                child: provider.tunnels.isEmpty
                    ? YsEmptyState(
                        icon: FLucideIcons.cloudOff,
                        title: 'No tunnels yet',
                        message:
                            'Add a tunnel to expose a local port via Cloudflare.',
                        action: session == null
                            ? const Text(
                                'Connect to a host first.',
                                style: TextStyle(
                                  color: YsColors.warn,
                                  fontSize: 12,
                                ),
                              )
                            : null,
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

  Future<void> _confirmRemove(TunnelConfig tunnel) async {
    final confirmed = await showYsConfirm(
      context,
      title: 'Remove tunnel',
      message: 'Remove "${tunnel.label}"?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed && mounted) {
      context.read<TunnelProvider>().remove(tunnel.id);
    }
  }

  Widget _buildTunnelTile(TunnelConfig tunnel, bool hasSession) {
    final statusColor = switch (tunnel.status) {
      TunnelStatus.idle => YsColors.off,
      TunnelStatus.starting => YsColors.warn,
      TunnelStatus.active => YsColors.ok,
      TunnelStatus.error => YsColors.error,
    };

    final Widget subtitle;
    if (tunnel.publicUrl != null) {
      subtitle = FTappable(
        semanticsLabel: tunnel.publicUrl!,
        onPress: () => launchUrl(Uri.parse(tunnel.publicUrl!)),
        child: Text(
          tunnel.publicUrl!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: YsColors.accentText, fontSize: 12),
        ),
      );
    } else if (tunnel.errorMessage != null) {
      subtitle = Text(
        tunnel.errorMessage!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: YsColors.error, fontSize: 11),
      );
    } else {
      subtitle = Text(
        'Port: ${tunnel.localPort}',
        style: const TextStyle(color: YsColors.mutedForeground, fontSize: 12),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.s3,
        vertical: YsSpace.s2,
      ),
      child: Row(
        children: [
          Icon(FLucideIcons.cloud, color: statusColor),
          const SizedBox(width: YsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tunnel.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: YsColors.foreground),
                ),
                subtitle,
              ],
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          if (tunnel.publicUrl != null)
            ContainerIconAction(
              icon: FLucideIcons.copy,
              tooltip: 'Copy URL',
              onPress: () =>
                  Clipboard.setData(ClipboardData(text: tunnel.publicUrl!)),
            ),
          if (tunnel.status == TunnelStatus.idle ||
              tunnel.status == TunnelStatus.error)
            ContainerIconAction(
              icon: FLucideIcons.play,
              tooltip: 'Start tunnel',
              active: true,
              onPress: hasSession ? () => _startTunnel(tunnel) : null,
            ),
          if (tunnel.status == TunnelStatus.active)
            ContainerIconAction(
              icon: FLucideIcons.square,
              tooltip: 'Stop tunnel',
              onPress: hasSession ? () => _stopTunnel(tunnel) : null,
            ),
          if (tunnel.status == TunnelStatus.starting)
            const Padding(
              padding: EdgeInsets.all(YsSpace.s2),
              child: ContainerSpinner(size: 16),
            ),
          ContainerIconAction(
            icon: FLucideIcons.trash2,
            tooltip: 'Remove',
            onPress: () => _confirmRemove(tunnel),
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
        color: YsColors.sidebar,
        border: Border(left: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: YsColors.border)),
            ),
            padding: const EdgeInsets.only(left: YsSpace.s4, right: YsSpace.s2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'New Cloudflare Tunnel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: YsColors.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ContainerIconAction(
                  icon: FLucideIcons.x,
                  tooltip: 'Close',
                  onPress: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                YsSpace.s4,
                YsSpace.s4,
                YsSpace.s4,
                YsSpace.s5,
              ),
              children: [
                DevopsTextField(
                  key: const ValueKey('tunnel-label'),
                  controller: _labelCtrl,
                  label: 'Label',
                  autofocus: true,
                ),
                const SizedBox(height: YsSpace.s3),
                DevopsTextField(
                  key: const ValueKey('tunnel-port'),
                  controller: _portCtrl,
                  label: 'Local Port',
                  number: true,
                ),
                const SizedBox(height: YsSpace.s5),
                FButton(
                  key: const ValueKey('tunnel-add'),
                  onPress: _submit,
                  child: const Text('Add Tunnel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
