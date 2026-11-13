part of 'host_detail_panel.dart';

/// GENERAL: label, then hostname and port side by side, so Tab runs
/// label → hostname → port → username. New hosts get the network scan in
/// the section caption (before the label in focus order).
class _GeneralSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _GeneralSection({required this.form});

  void _scan(BuildContext context) => NetworkDiscoverySheet.show(
    context,
    selectionMode: true,
    onSelected: (h) {
      form._set(() {
        form._hostCtrl.text = h.ip;
        form._portCtrl.text =
            (h.isRdp
                    ? 3389
                    : (h.openPorts.contains(22) ? 22 : h.openPorts.first))
                .toString();
        if (h.hostname != null && form._labelCtrl.text.isEmpty) {
          form._labelCtrl.text = h.hostname!;
        }
        if (h.isRdp && form._protocol != HostProtocol.rdp) {
          form._onProtocolChanged(HostProtocol.rdp);
        }
      });
    },
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(
          'GENERAL',
          trailing: form._isNew
              ? Align(
                  alignment: Alignment.centerRight,
                  child: FButton(
                    variant: .ghost,
                    size: .xs,
                    mainAxisSize: MainAxisSize.min,
                    prefix: const Icon(FLucideIcons.radar),
                    onPress: () => _scan(context),
                    child: _buttonText('Scan network to pick a device'),
                  ),
                )
              : null,
        ),
        _Field(
          key: const ValueKey('host-label-field'),
          controller: form._labelCtrl,
          label: 'Label',
          hint: 'Label',
          onSubmit: form._submit,
        ),
        _fieldGap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Field(
                key: const ValueKey('host-address-field'),
                controller: form._hostCtrl,
                label: 'Hostname or IP',
                hint: 'IP or Hostname',
                autofocus: true,
                onSubmit: form._submit,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: YsSpace.s2),
            SizedBox(
              width: 76,
              child: _Field(
                key: const ValueKey('host-port-field'),
                controller: form._portCtrl,
                // "SSH on / RDP on / VNC on" — the port belongs to the
                // selected protocol.
                label: switch (form._protocol) {
                  HostProtocol.ssh => 'SSH on',
                  HostProtocol.rdp => 'RDP on',
                  HostProtocol.vnc => 'VNC on',
                },
                hint: 'port',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmit: form._submit,
                validator: _HostDetailPanelState._validatePortShort,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// GROUP & TAGS: free-text group and comma-separated tags.
class _GroupTagsSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _GroupTagsSection({required this.form});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('GROUP & TAGS'),
        _Field(
          key: const ValueKey('host-group-field'),
          controller: form._groupCtrl,
          label: 'Group',
          hint: 'Group',
          icon: FLucideIcons.folder,
          onSubmit: form._submit,
        ),
        _fieldGap,
        _Field(
          key: const ValueKey('host-tags-field'),
          controller: form._tagsCtrl,
          label: 'Tags',
          hint: 'Tags, e.g. env:prod, role:db',
          icon: FLucideIcons.tag,
          onSubmit: form._submit,
        ),
      ],
    );
  }
}
