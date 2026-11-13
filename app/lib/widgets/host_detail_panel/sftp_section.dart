part of 'host_detail_panel.dart';

/// SFTP MODE (SSH only): default / sudo / custom server command.
class _SftpSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _SftpSection({required this.form});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('SFTP MODE'),
        _Select<SftpMode>(
          key: const ValueKey('sftp-mode-select'),
          icon: FLucideIcons.shieldUser,
          value: form._sftpMode,
          options: const [
            (SftpMode.normal, 'Default'),
            (SftpMode.sudo, 'Sudo (root)'),
            (SftpMode.custom, 'Custom command'),
          ],
          onChanged: (v) => form._set(() => form._sftpMode = v),
        ),
        if (form._sftpMode == SftpMode.custom) ...[
          _fieldGap,
          _Field(
            key: const ValueKey('sftp-command-field'),
            controller: form._sftpCommand,
            hint: 'sudo /usr/lib/openssh/sftp-server',
            icon: FLucideIcons.squareTerminal,
            onSubmit: form._submit,
            validator: (v) =>
                form._sftpMode == SftpMode.custom &&
                    (v == null || v.trim().isEmpty)
                ? 'Required'
                : null,
          ),
        ],
      ],
    );
  }
}
