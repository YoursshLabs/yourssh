import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import 'settings_tiles.dart';

/// Settings → Monitoring: network stats overlay and command-finish alerts.
class MonitoringSettingsSection extends StatelessWidget {
  const MonitoringSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    SettingsProvider write() => context.read<SettingsProvider>();
    return SettingsSection(
      title: 'Monitoring',
      tiles: [
        settingsSwitchTile(
          key: const ValueKey('settings-network-stats'),
          label: 'Network Stats Monitor',
          description: 'Show Rx/Tx overlay on active session',
          value: settings.networkStatsEnabled,
          onChange: (v) => write().save(networkStatsEnabled: v),
        ),
        settingsSwitchTile(
          key: const ValueKey('settings-command-notifications'),
          label: 'Command finish notification',
          description: 'Alert when a command completes in an unfocused session',
          value: settings.commandNotificationsEnabled,
          onChange: (v) => write().save(commandNotificationsEnabled: v),
        ),
      ],
    );
  }
}
