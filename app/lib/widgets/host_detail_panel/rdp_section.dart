part of 'host_detail_panel.dart';

/// RDP SECURITY (RDP only): auto / NLA / TLS.
class _RdpSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _RdpSection({required this.form});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('RDP SECURITY'),
        _Select<RdpSecurityMode>(
          key: const ValueKey('rdp-security-select'),
          icon: FLucideIcons.shield,
          value: form._rdpSecurity,
          options: const [
            (RdpSecurityMode.auto, 'Auto (negotiate)'),
            (RdpSecurityMode.nla, 'NLA (CredSSP)'),
            (RdpSecurityMode.tls, 'TLS only'),
          ],
          onChanged: (v) => form._set(() => form._rdpSecurity = v),
        ),
      ],
    );
  }
}
