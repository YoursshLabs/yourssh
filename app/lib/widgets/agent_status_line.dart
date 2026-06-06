import 'package:flutter/material.dart';

import '../services/agent_probe.dart';
import '../theme/app_theme.dart';

/// One-line live agent status under the Agent forwarding toggle / SSH Agent
/// auth picker. Probes automatically on mount (zero-click feedback); the
/// refresh icon re-probes after the user changes their agent setup.
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
          Icons.hourglass_empty,
          AppColors.textTertiary,
          'Checking SSH agent…',
        ),
      AgentProbeSystem(:final identityCount) => (
          Icons.check_circle_outline,
          AppColors.accent,
          'System agent connected — $identityCount '
              '${identityCount == 1 ? 'identity' : 'identities'}',
        ),
      AgentProbeKeychain(:final keyCount) => (
          Icons.info_outline,
          AppColors.orange,
          'No system agent — $keyCount app Keychain '
              '${keyCount == 1 ? 'key' : 'keys'} will be offered instead',
        ),
      AgentProbeNothing(:final detail) => (
          Icons.error_outline,
          AppColors.red,
          detail == null
              ? 'No agent and no usable Keychain keys — forwarding will '
                  'offer nothing. Run "ssh-add <key>" or add a key in '
                  'Keychain.'
              : 'SSH agent error: $detail',
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 11, height: 1.3)),
          ),
          // While a probe is in flight the refresh affordance becomes a
          // spinner — taps are blocked and the user sees progress.
          _result == null
              ? const Padding(
                  padding: EdgeInsets.all(2),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppColors.textTertiary),
                  ),
                )
              : InkWell(
                  onTap: _run,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.refresh,
                        size: 13, color: AppColors.textTertiary),
                  ),
                ),
        ],
      ),
    );
  }
}
