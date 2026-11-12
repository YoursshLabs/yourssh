import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import 'settings_tiles.dart';

/// Settings → Connection: reconnect policy, keep-alive, tmux and shell
/// integration.
class ConnectionSettingsSection extends StatelessWidget {
  const ConnectionSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    SettingsProvider write() => context.read<SettingsProvider>();
    return SettingsSection(
      title: 'Connection',
      tiles: [
        settingsSwitchTile(
          key: const ValueKey('settings-auto-reconnect'),
          label: 'Auto-reconnect',
          description: 'Reconnect when connection drops',
          value: settings.autoReconnect,
          onChange: (v) => write().save(autoReconnect: v),
        ),
        settingsRowTile(
          label: 'Max reconnect attempts',
          trailing: SettingsSelect<int>(
            key: const ValueKey('settings-reconnect-attempts'),
            value: settings.reconnectAttempts,
            options: [
              for (final n in const [0, 1, 3, 5, 10])
                (n, n == 0 ? 'Unlimited' : '$n times'),
            ],
            onChanged: (v) => write().save(reconnectAttempts: v),
          ),
        ),
        settingsRowTile(
          label: 'Keep-alive interval',
          description:
              'How often to ping the server to keep the connection alive',
          trailing: SettingsSelect<int>(
            key: const ValueKey('settings-keep-alive'),
            value: settings.keepAliveInterval,
            options: [
              for (final n in const [10, 30, 60, 0])
                (n, n == 0 ? 'Off' : '${n}s'),
            ],
            onChanged: (v) => write().save(keepAliveInterval: v),
          ),
        ),
        settingsSwitchTile(
          key: const ValueKey('settings-tmux'),
          label: 'Tmux Integration',
          description:
              'Attach to tmux session on connect (requires tmux on server)',
          value: settings.tmuxEnabled,
          onChange: (v) => write().save(tmuxEnabled: v),
        ),
        settingsSwitchTile(
          key: const ValueKey('settings-shell-integration'),
          label: 'Shell Integration',
          description:
              'Detect cwd, command status & exit codes on bash/zsh (cwd in '
              'tab, gutter markers, jump-to-prompt, path completion)',
          value: settings.shellIntegrationEnabled,
          onChange: (v) => write().save(shellIntegrationEnabled: v),
        ),
      ],
    );
  }
}
