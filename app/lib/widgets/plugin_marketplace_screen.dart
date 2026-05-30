import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../providers/plugin_provider.dart';
import '../theme/app_theme.dart';

class PluginMarketplaceScreen extends StatelessWidget {
  const PluginMarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pluginProvider = context.watch<PluginProvider>();
    final plugins = pluginProvider.plugins;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Plugins',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Installed plugins. Add plugins by editing plugin_registry.dart and rebuilding.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        if (plugins.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No plugins installed.',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: plugins.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) =>
                  _PluginTile(plugin: plugins[index]),
            ),
          ),
      ],
    );
  }
}

class _PluginTile extends StatelessWidget {
  final YourSSHPlugin plugin;
  const _PluginTile({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final pluginProvider = context.watch<PluginProvider>();
    final enabled = pluginProvider.isEnabled(plugin.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(plugin.icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plugin.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'v${plugin.version}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  plugin.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (_) => pluginProvider.toggle(plugin.id),
            activeThumbColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
