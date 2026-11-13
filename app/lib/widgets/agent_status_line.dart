import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../services/agent_probe.dart';

/// One-line live agent status under the Agent forwarding toggle / SSH Agent
/// auth picker. Probes automatically on mount (zero-click feedback); the
/// refresh button re-probes after the user changes their agent setup.
class AgentStatusLine extends StatefulWidget {
  const AgentStatusLine({super.key, required this.probe});

  final Future<AgentProbeResult> Function() probe;

  @override
  State<AgentStatusLine> createState() => _AgentStatusLineState();
}

class _AgentStatusLineState extends State<AgentStatusLine> {
  AgentProbeResult? _result; // null = probe in flight

  @override
  void initState() {
    super.initState();
    _runInitial();
  }

  /// Called from initState — avoids calling setState before the first build.
  Future<void> _runInitial() async {
    final result = await widget.probe();
    if (mounted) setState(() => _result = result);
  }

  Future<void> _run() async {
    setState(() => _result = null);
    final result = await widget.probe();
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (_result) {
      null => (
        FLucideIcons.hourglass,
        YsColors.mutedForeground,
        'Checking SSH agent…',
      ),
      AgentProbeSystem(:final identityCount) => (
        FLucideIcons.circleCheck,
        YsColors.ok,
        'System agent connected — $identityCount '
            '${identityCount == 1 ? 'identity' : 'identities'}',
      ),
      AgentProbeKeychain(:final keyCount) => (
        FLucideIcons.info,
        YsColors.warn,
        'No system agent — $keyCount app Keychain '
            '${keyCount == 1 ? 'key' : 'keys'} will be offered instead',
      ),
      AgentProbeNothing(:final detail) => (
        FLucideIcons.circleAlert,
        YsColors.error,
        detail == null
            ? 'No agent and no usable Keychain keys — forwarding will '
                  'offer nothing. Run "ssh-add <key>" or add a key in '
                  'Keychain.'
            : 'SSH agent error: $detail',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: 12, height: 1.35),
              ),
            ),
          ),
          // While a probe is in flight the refresh button becomes a spinner
          // — taps are blocked and the user sees progress.
          SizedBox(
            width: 24,
            height: 24,
            child: _result == null
                ? const Center(child: FCircularProgress(size: .sm))
                : Tooltip(
                    message: 'Check again',
                    excludeFromSemantics: true,
                    child: FButton.icon(
                      variant: .ghost,
                      size: .xs,
                      semanticsLabel: 'Check again',
                      onPress: _run,
                      child: const Icon(FLucideIcons.refreshCw),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
