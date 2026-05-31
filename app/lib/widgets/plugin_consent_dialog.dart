import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../providers/plugin_engine_provider.dart';
import '../theme/app_theme.dart';

class PluginConsentDialog extends StatefulWidget {
  final PluginManifest manifest;
  const PluginConsentDialog({super.key, required this.manifest});

  @override
  State<PluginConsentDialog> createState() => _PluginConsentDialogState();
}

class _PluginConsentDialogState extends State<PluginConsentDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.manifest.permissions);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Install "${widget.manifest.name}"',
          style: const TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.manifest.id} · v${widget.manifest.version}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              if (widget.manifest.permissions.isEmpty)
                const Text('This plugin requests no special permissions.',
                    style: TextStyle(color: AppColors.textSecondary))
              else ...[
                const Text('This plugin requests:',
                    style: TextStyle(color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                ...widget.manifest.permissions.map((perm) => CheckboxListTile(
                      dense: true,
                      title: Text(perm,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                      value: _selected.contains(perm),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(perm);
                        } else {
                          _selected.remove(perm);
                        }
                      }),
                    )),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.read<PluginEngineProvider>().denyConsent();
            Navigator.of(context).pop();
          },
          child: const Text('Deny'),
        ),
        ElevatedButton(
          onPressed: () async {
            final provider = context.read<PluginEngineProvider>();
            Navigator.of(context).pop();
            await provider.approveConsent(Set.from(_selected));
          },
          child: const Text('Allow selected'),
        ),
      ],
    );
  }
}
