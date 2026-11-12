part of 'host_detail_panel.dart';

/// SSH / RDP / VNC switch at the top of the form ([FTabs] used as a
/// segmented control: the tabs carry no content of their own).
class _ProtocolSwitch extends StatelessWidget {
  final _HostDetailPanelState form;
  const _ProtocolSwitch({required this.form});

  static const _tabs = [
    (HostProtocol.ssh, FLucideIcons.squareTerminal, 'SSH'),
    (HostProtocol.rdp, FLucideIcons.monitor, 'RDP'),
    (HostProtocol.vnc, FLucideIcons.cast, 'VNC'),
  ];

  @override
  Widget build(BuildContext context) {
    return FTabs(
      key: const ValueKey('host-protocol-tabs'),
      control: .lifted(
        index: _tabs.indexWhere((t) => t.$1 == form._protocol),
        onChange: (i) => form._onProtocolChanged(_tabs[i].$1),
      ),
      children: [
        for (final (_, icon, label) in _tabs)
          FTabEntry(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
            child: const SizedBox.shrink(),
          ),
      ],
    );
  }
}
