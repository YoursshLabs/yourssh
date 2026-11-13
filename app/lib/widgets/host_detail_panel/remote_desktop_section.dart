part of 'host_detail_panel.dart';

/// Sections shared by the graphical protocols (RDP and VNC; VNC has no
/// fields of its own): CLIPBOARD and the single-hop SSH TUNNEL.
class _RemoteDesktopSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _RemoteDesktopSection({required this.form});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('CLIPBOARD'),
        FTileGroup(
          children: [
            _switchTile(
              key: const ValueKey('remote-clipboard-switch'),
              title: 'Accept remote clipboard',
              description:
                  'Let the remote desktop replace your local '
                  'clipboard (max 1 MiB). Turn off for untrusted '
                  'hosts.',
              value: form._remoteClipboard,
              onChange: (v) => form._set(() => form._remoteClipboard = v),
            ),
          ],
        ),
        // SSH tunnel applies to any graphical protocol (RDP + VNC).
        _tunnel(context),
      ],
    );
  }

  Widget _tunnel(BuildContext context) {
    final sshHosts = context
        .watch<HostProvider>()
        .allHosts
        .where(
          (h) =>
              h.protocol == HostProtocol.ssh &&
              h.id != form.widget.existing?.id,
        )
        .toList();
    if (sshHosts.isEmpty) return const SizedBox.shrink();
    // A deleted bastion leaves a stale id — show "Direct connection"
    // instead of a value the select does not know.
    final current = form._jumpHostIds.firstOrNull;
    final valid = sshHosts.any((h) => h.id == current) ? current : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('SSH TUNNEL'),
        _Select<String?>(
          key: const ValueKey('ssh-tunnel-select'),
          icon: FLucideIcons.route,
          value: valid,
          options: [
            (null, 'Direct connection'),
            for (final h in sshHosts)
              (h.id, 'via ${h.label.isEmpty ? h.host : h.label}'),
          ],
          onChanged: (v) =>
              form._set(() => form._jumpHostIds = v == null ? [] : [v]),
        ),
      ],
    );
  }
}
