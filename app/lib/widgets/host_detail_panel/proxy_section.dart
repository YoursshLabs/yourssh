part of 'host_detail_panel.dart';

/// PROXY (SSH only): none / HTTP CONNECT / SOCKS5 and its endpoint.
class _ProxySection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _ProxySection({required this.form});

  @override
  Widget build(BuildContext context) {
    final on = form._proxyType != ProxyType.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('PROXY'),
        _Select<ProxyType>(
          key: const ValueKey('proxy-type-dropdown'),
          label: 'Type',
          icon: FLucideIcons.waypoints,
          value: form._proxyType,
          options: const [
            (ProxyType.none, 'None'),
            (ProxyType.http, 'HTTP CONNECT'),
            (ProxyType.socks5, 'SOCKS5'),
          ],
          onChanged: (v) => form._set(() => form._proxyType = v),
        ),
        if (on) ...[
          _fieldGap,
          _Field(
            key: const ValueKey('proxy-host-field'),
            controller: form._proxyHostCtrl,
            hint: 'Proxy host',
            icon: FLucideIcons.server,
            onSubmit: form._submit,
          ),
          _fieldGap,
          _Field(
            key: const ValueKey('proxy-port-field'),
            controller: form._proxyPortCtrl,
            hint: 'Proxy port',
            icon: FLucideIcons.hash,
            keyboardType: TextInputType.number,
            onSubmit: form._submit,
          ),
          _fieldGap,
          _Field(
            key: const ValueKey('proxy-username-field'),
            controller: form._proxyUsernameCtrl,
            hint: 'Proxy username (optional)',
            icon: FLucideIcons.user,
            onSubmit: form._submit,
          ),
          _fieldGap,
          _PasswordField(
            key: const ValueKey('proxy-password-field'),
            controller: form._proxyPasswordCtrl,
            icon: FLucideIcons.keyRound,
            onSubmit: form._submit,
          ),
        ],
      ],
    );
  }
}
