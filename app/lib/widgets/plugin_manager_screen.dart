import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_engine_provider.dart';
import '../theme/app_theme.dart';
import 'plugin_consent_dialog.dart';

class PluginManagerScreen extends StatelessWidget {
  const PluginManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginEngineProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (provider.pendingConsent != null)
            Card(
              color: AppColors.card,
              child: ListTile(
                leading: const Icon(Icons.extension, color: Colors.amber),
                title: Text(
                  'New plugin: ${provider.pendingConsent!.name}',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  provider.pendingConsent!.id,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => PluginConsentDialog(
                        manifest: provider.pendingConsent!),
                  ),
                  child: const Text('Review'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Script plugins are loaded from ~/.yourssh/plugins/\n'
            'Each plugin directory must contain a plugin.json manifest and an index.js entry point.\n'
            'Changes to plugin files are hot-reloaded automatically.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
