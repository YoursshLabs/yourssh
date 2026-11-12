import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/port_forward.dart';
import '../../providers/port_forward_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../container_widgets.dart';

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
      return const YsEmptyState(
        icon: FLucideIcons.router,
        title: 'No active local tunnels',
        message:
            'Start a local port forward in the Port Forwarding section\nto open it here.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 52,
          color: YsColors.sidebar,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: const Text(
            'Active Local Tunnels',
            style: TextStyle(
              color: YsColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const FDivider(style: .delta(padding: .value(EdgeInsets.zero))),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(YsSpace.s4),
            itemCount: localActive.length,
            separatorBuilder: (_, _) =>
                const FDivider(style: .delta(padding: .value(EdgeInsets.zero))),
            itemBuilder: (_, i) =>
                _TunnelRow(forward: localActive[i], onOpenUrl: onOpenUrl),
          ),
        ),
      ],
    );
  }
}

class _TunnelRow extends StatelessWidget {
  final PortForward forward;
  final ValueChanged<String> onOpenUrl;
  const _TunnelRow({required this.forward, required this.onOpenUrl});

  String get _url => 'http://${forward.localHost}:${forward.localPort}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.s3,
        vertical: YsSpace.s3,
      ),
      decoration: BoxDecoration(
        color: YsColors.card,
        borderRadius: BorderRadius.circular(YsRadius.control),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: YsColors.ok,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: YsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forward.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 12,
                    fontFamily: kYsMonoFontFamily,
                    fontFamilyFallback: kYsMonoFontFallback,
                  ),
                ),
              ],
            ),
          ),
          ContainerIconAction(
            icon: FLucideIcons.copy,
            tooltip: 'Copy URL',
            onPress: () => Clipboard.setData(ClipboardData(text: _url)),
          ),
          const SizedBox(width: YsSpace.s2),
          FButton(
            mainAxisSize: MainAxisSize.min,
            size: .sm,
            onPress: () => onOpenUrl(_url),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
