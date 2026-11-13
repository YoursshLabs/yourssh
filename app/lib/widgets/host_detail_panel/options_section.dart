part of 'host_detail_panel.dart';

/// OPTIONS (SSH only): auto-record, recording redaction, shell integration,
/// agent forwarding (+ status line) and OSC 52 clipboard, as [FSwitch]es in
/// an [FTileGroup].
class _OptionsSection extends StatelessWidget {
  final _HostDetailPanelState form;
  const _OptionsSection({required this.form});

  static const _forwardingHelp =
      'SSH Agent auth: your agent\'s keys log you in '
      'to THIS host.\n'
      'Agent forwarding: this host can borrow your '
      'local keys to reach other places (git pull, '
      'ssh to the next hop). Private keys never '
      'leave your machine.\n'
      'Only enable for trusted hosts — root on the '
      'host can use your keys while you are '
      'connected.';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('OPTIONS'),
        FTileGroup(
          children: [
            _switchTile(
              key: const ValueKey('auto-record-switch'),
              title: 'Auto-record sessions',
              description: 'Start recording automatically on connect',
              value: form._autoRecord,
              onChange: (v) => form._set(() => form._autoRecord = v),
            ),
            _switchTile(
              key: const ValueKey('recording-redaction-switch'),
              title: 'Redact secrets in recordings',
              description:
                  'Mask passwords/tokens before writing .cast (requires the '
                  'global setting)',
              value: form._recordingRedaction,
              onChange: (v) => form._set(() => form._recordingRedaction = v),
            ),
            _switchTile(
              key: const ValueKey('shell-integration-switch'),
              title: 'Shell integration',
              description: 'cwd, command status & path completion on bash/zsh',
              value: form._shellIntegration,
              onChange: (v) => form._set(() => form._shellIntegration = v),
            ),
            _switchTile(
              key: const ValueKey('agent-forwarding-switch'),
              title: 'Agent forwarding',
              titleWidget: const Text.rich(
                TextSpan(
                  text: 'Agent forwarding ',
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Tooltip(
                        message: _forwardingHelp,
                        child: Icon(
                          FLucideIcons.info,
                          size: 13,
                          color: YsColors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              description:
                  'Let this host use your local SSH keys for onward '
                  'connections — git, ssh to other servers (like '
                  'ssh -A). Applies on next connect.',
              value: form._agentForwarding,
              onChange: (v) => form._set(() => form._agentForwarding = v),
            ),
            _switchTile(
              key: const ValueKey('osc52-switch'),
              title: 'OSC 52 clipboard',
              description:
                  'Let remote apps (tmux, vim) set your local clipboard. '
                  'Write-only. Off by default — only enable for hosts you '
                  'trust.',
              value: form._osc52Clipboard,
              onChange: (v) => form._set(() => form._osc52Clipboard = v),
            ),
          ],
        ),
        // Zero-click feedback: probes on appearance. The auth section owns
        // the line when auth = SSH Agent (spec: one probe, no duplicate row).
        if (form._agentForwarding && form._authType != AuthType.agent)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.s2),
            child: AgentStatusLine(
              key: const ValueKey('forwarding-status'),
              probe: form._probeAgent,
            ),
          ),
      ],
    );
  }
}
