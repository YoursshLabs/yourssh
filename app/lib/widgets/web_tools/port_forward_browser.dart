import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/port_forward.dart';
import '../../providers/port_forward_provider.dart';
import '../../theme/app_theme.dart';

class PortForwardBrowser extends StatelessWidget {
  final ValueChanged<String> onOpenUrl;
  const PortForwardBrowser({super.key, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortForwardProvider>();
    final localActive = provider.forwards
        .where((f) =>
            f.type == ForwardType.local && f.status == ForwardStatus.active)
        .toList();

    if (localActive.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.router_outlined, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text('No active local tunnels',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Start a local port forward in the Port Forwarding section\nto open it here.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 52,
          color: AppColors.sidebar,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: const Text('Active Local Tunnels',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        const Divider(height: 1, color: AppColors.border),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: localActive.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) =>
                _TunnelRow(forward: localActive[i], onOpenUrl: onOpenUrl),
          ),
        ),
      ],
    );
  }
}

class _TunnelRow extends StatefulWidget {
  final PortForward forward;
  final ValueChanged<String> onOpenUrl;
  const _TunnelRow({required this.forward, required this.onOpenUrl});

  @override
  State<_TunnelRow> createState() => _TunnelRowState();
}

class _TunnelRowState extends State<_TunnelRow> {
  bool _hovered = false;

  String get _url =>
      'http://${widget.forward.localHost}:${widget.forward.localPort}';

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.forward.label,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(_url,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 14),
              color: AppColors.textTertiary,
              tooltip: 'Copy URL',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Clipboard.setData(ClipboardData(text: _url)),
            ),
            const SizedBox(width: 8),
            _OpenButton(onTap: () => widget.onOpenUrl(_url)),
          ],
        ),
      ),
    );
  }
}

class _OpenButton extends StatefulWidget {
  final VoidCallback onTap;
  const _OpenButton({required this.onTap});

  @override
  State<_OpenButton> createState() => _OpenButtonState();
}

class _OpenButtonState extends State<_OpenButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.accentDim : AppColors.accent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Text('Open',
              style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
