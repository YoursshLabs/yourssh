import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../models/ssh_key.dart';
import '../providers/host_provider.dart';
import '../services/key_gen_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// ssh-copy-id-style deploy: pick a saved host, append [entry]'s public
/// key to its ~/.ssh/authorized_keys (idempotent via grep -qxF). Failures
/// keep the dialog open for retry.
class DeployKeyDialog extends StatefulWidget {
  final SshKeyEntry entry;
  const DeployKeyDialog({super.key, required this.entry});

  @override
  State<DeployKeyDialog> createState() => _DeployKeyDialogState();
}

class _DeployKeyDialogState extends State<DeployKeyDialog> {
  String _search = '';
  String? _busyHostId;
  String? _error;

  Future<void> _deploy(Host host) async {
    setState(() {
      _busyHostId = host.id;
      _error = null;
    });
    try {
      final cmd = KeyGenService.buildDeployCommand(widget.entry.publicKey);
      final r = await context.read<SshService>().exec(host, cmd);
      if (!mounted) return;
      if (r.exitCode == 0) {
        final added = r.stdout.contains('ADDED');
        Navigator.pop(context);
        AppSnack.success(
            context,
            added
                ? 'Public key added to ${host.label}'
                : 'Key already deployed on ${host.label}');
      } else {
        setState(() => _error = 'Failed on ${host.label}: '
            '${r.stderr.trim().isEmpty ? 'exit ${r.exitCode}' : r.stderr.trim()}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed on ${host.label}: $e');
    } finally {
      if (mounted) setState(() => _busyHostId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final hosts = context
        .watch<HostProvider>()
        .allHosts
        .where((h) =>
            q.isEmpty ||
            h.label.toLowerCase().contains(q) ||
            h.host.toLowerCase().contains(q))
        .toList();

    return YsDialog(
      title: 'Deploy "${widget.entry.label}" to host',
      body: SizedBox(
        width: 380,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextField(
              key: const Key('deploy-key-search'),
              autofocus: true,
              hint: 'Search hosts…',
              autocorrect: false,
              enableSuggestions: false,
              control: FTextFieldControl.managed(
                onChange: (v) => setState(() => _search = v.text),
              ),
              prefixBuilder: (context, style, variants) =>
                  FTextField.prefixIconBuilder(
                    context,
                    style,
                    variants,
                    const Icon(FLucideIcons.search),
                  ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: YsSpace.s2),
                child: Text(
                  _error!,
                  style: const TextStyle(color: YsColors.error, fontSize: 12),
                ),
              ),
            const SizedBox(height: YsSpace.s2),
            Expanded(
              child: hosts.isEmpty
                  ? const Center(
                      child: Text(
                        'No hosts',
                        style: TextStyle(
                          color: YsColors.mutedForeground,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: hosts.length,
                      itemBuilder: (_, i) {
                        final h = hosts[i];
                        final busy = _busyHostId == h.id;
                        return FTile(
                          enabled: _busyHostId == null,
                          prefix: const Icon(FLucideIcons.server),
                          title: Text(
                            h.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${h.username}@${h.host}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          suffix: busy
                              ? const FCircularProgress(size: .sm)
                              : null,
                          onPress: () => _deploy(h),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
