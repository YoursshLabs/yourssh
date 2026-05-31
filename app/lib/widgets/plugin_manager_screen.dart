import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_engine_provider.dart';
import '../providers/plugin_provider.dart';
import '../theme/app_theme.dart';
import 'plugin_consent_dialog.dart';
import 'plugin_console_screen.dart';

class PluginManagerScreen extends StatelessWidget {
  const PluginManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engineProvider = context.watch<PluginEngineProvider>();
    final pluginProvider = context.watch<PluginProvider>();
    final jsPlugins = engineProvider.loadedPlugins;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (engineProvider.pendingConsent != null)
            Card(
              color: AppColors.card,
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: const Icon(Icons.extension, color: Colors.amber),
                title: Text(
                  'New plugin: ${engineProvider.pendingConsent!.name}',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  engineProvider.pendingConsent!.id,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => PluginConsentDialog(
                        manifest: engineProvider.pendingConsent!),
                  ),
                  child: const Text('Review'),
                ),
              ),
            ),

          // Dart plugins
          const Text(
            'BUILT-IN PLUGINS',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          if (pluginProvider.plugins.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No built-in plugins registered.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...pluginProvider.plugins.map((plugin) {
              final enabled = pluginProvider.isEnabled(plugin.id);
              return Card(
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(plugin.icon,
                      color: enabled
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      size: 20),
                  title: Text(
                    plugin.name,
                    style: TextStyle(
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    plugin.description,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: Switch(
                    value: enabled,
                    onChanged: (_) => pluginProvider.toggle(plugin.id),
                    activeThumbColor: AppColors.accent,
                  ),
                ),
              );
            }),

          const SizedBox(height: 16),

          // JS / script plugins
          const Text(
            'SCRIPT PLUGINS',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          if (jsPlugins.isEmpty) ...[
            const Text(
              'No script plugins loaded.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'Drop a plugin folder into ~/.yourssh/plugins/\n'
              'Each folder needs plugin.json + index.js. Hot-reloaded on change.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ] else ...[
            for (final manifest in jsPlugins)
              Card(
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.code,
                      color: AppColors.accent, size: 20),
                  title: Text(
                    manifest.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '${manifest.id}  •  v${manifest.version}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.terminal,
                        color: AppColors.textSecondary, size: 18),
                    tooltip: 'View logs',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PluginConsoleScreen(pluginId: manifest.id),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Text(
              'Loaded from ~/.yourssh/plugins/ — hot-reloaded on change.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
