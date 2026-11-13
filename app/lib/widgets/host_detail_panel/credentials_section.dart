part of 'host_detail_panel.dart';

/// CREDENTIALS: username, password and (RDP) domain.
class _CredentialsSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _CredentialsSection({required this.form});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('CREDENTIALS'),
        _Field(
          key: const ValueKey('host-username-field'),
          controller: form._usernameCtrl,
          label: 'Username',
          hint: 'Username',
          onSubmit: form._submit,
        ),
        _fieldGap,
        _PasswordField(
          key: const ValueKey('host-password-field'),
          controller: form._passwordCtrl,
          label: 'Password',
          onSubmit: form._submit,
        ),
        if (form._isRdp) ...[
          _fieldGap,
          _Field(
            key: const ValueKey('host-domain-field'),
            controller: form._domainCtrl,
            label: 'Domain',
            hint: 'Domain (optional)',
            onSubmit: form._submit,
          ),
        ],
      ],
    );
  }
}

/// AUTH METHOD (SSH only): password / private key / agent, the key picker
/// and the agent status line.
class _AuthMethodSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _AuthMethodSection({required this.form});

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('AUTH METHOD'),
        _Select<AuthType>(
          key: const ValueKey('auth-method-select'),
          icon: FLucideIcons.lockKeyhole,
          value: form._authType,
          options: const [
            (AuthType.password, 'Password'),
            (AuthType.privateKey, 'Private Key'),
            (AuthType.agent, 'SSH Agent'),
          ],
          onChanged: (v) => form._set(() {
            form._authType = v;
            form._selectedKeyId = null;
            form._testResult = null;
          }),
        ),
        if (form._authType == AuthType.privateKey) ...[
          _fieldGap,
          _Select<String?>(
            key: const ValueKey('auth-key-select'),
            icon: FLucideIcons.keyRound,
            hint: 'Select key',
            value: form._selectedKeyId,
            options: [
              for (final k in keys) (k.id, '${k.label} (${k.algorithmLabel})'),
            ],
            onChanged: (v) => form._set(() {
              form._selectedKeyId = v;
              form._testResult = null;
            }),
          ),
        ],
        if (form._authType == AuthType.agent)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.s2),
            child: AgentStatusLine(
              key: const ValueKey('auth-agent-status'),
              probe: form._probeAgent,
            ),
          ),
      ],
    );
  }
}
