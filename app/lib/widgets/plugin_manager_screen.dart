import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../providers/plugin_engine_provider.dart';
import '../providers/plugin_provider.dart';
import 'plugin_consent_dialog.dart';
import 'plugin_console_screen.dart';
import 'settings/settings_tiles.dart';
import 'switch_row_tile.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class PluginManagerScreen extends StatelessWidget {
  const PluginManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engineProvider = context.watch<PluginEngineProvider>();
    final pluginProvider = context.watch<PluginProvider>();
    final jsPlugins = engineProvider.loadedPlugins;
    final pending = engineProvider.pendingConsent;

    return ColoredBox(
      color: YsColors.background,
      child: ListView(
        padding: const EdgeInsets.all(YsSpace.s4),
        children: [
          if (pending != null) ...[
            settingsTileGroup(
              children: [
                FTile(
                  prefix: const Icon(
                    FLucideIcons.puzzle,
                    color: YsColors.primary,
                  ),
                  title: Text(
                    'New plugin: ${pending.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    pending.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  suffix: FButton(
                    size: .xs,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => showYsDialog(
                      context,
                      barrierDismissible: false,
                      builder: (_) => PluginConsentDialog(manifest: pending),
                    ),
                    child: const Text('Review'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: YsSpace.s4),
          ],

          // Dart plugins
          const YsSectionHeader(title: 'BUILT-IN PLUGINS'),
          if (pluginProvider.plugins.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: YsSpace.s4),
              child: Text(
                'No built-in plugins registered.',
                style: TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 13,
                ),
              ),
            )
          else
            settingsTileGroup(
              children: [
                for (final plugin in pluginProvider.plugins)
                  _builtInTile(pluginProvider, plugin),
              ],
            ),

          const SizedBox(height: YsSpace.s4),

          // JS / script plugins
          const YsSectionHeader(title: 'SCRIPT PLUGINS'),
          if (jsPlugins.isEmpty) ...[
            const Text(
              'No script plugins loaded.',
              style: TextStyle(color: YsColors.mutedForeground, fontSize: 13),
            ),
            const SizedBox(height: YsSpace.s2),
            const Text(
              'Drop a plugin folder into ~/.yourssh/plugins/\n'
              'Each folder needs plugin.json + index.js. Hot-reloaded on change.',
              style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
            ),
          ] else ...[
            settingsTileGroup(
              children: [
                for (final manifest in jsPlugins)
                  FTile(
                    prefix: const Icon(
                      FLucideIcons.code,
                      color: YsColors.primary,
                    ),
                    title: Text(
                      manifest.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${manifest.id}  •  v${manifest.version}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    suffix: SettingsIconButton(
                      icon: FLucideIcons.terminal,
                      tooltip: 'View logs',
                      onPress: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PluginConsoleScreen(pluginId: manifest.id),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: YsSpace.s2),
            const Text(
              'Loaded from ~/.yourssh/plugins/ — hot-reloaded on change.',
              style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  FTile _builtInTile(PluginProvider pluginProvider, YourSSHPlugin plugin) {
    final enabled = pluginProvider.isEnabled(plugin.id);
    return switchRowTile(
      key: ValueKey('plugin-switch-${plugin.id}'),
      label: Row(
        children: [
          Icon(
            plugin.icon,
            size: 20,
            color: enabled ? YsColors.primary : YsColors.mutedForeground,
          ),
          const SizedBox(width: YsSpace.s3),
          Expanded(
            child: Text(
              plugin.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: enabled ? YsColors.foreground : YsColors.mutedForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      description: Text(
        plugin.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      value: enabled,
      onChange: (_) => pluginProvider.toggle(plugin.id),
    );
  }
}
