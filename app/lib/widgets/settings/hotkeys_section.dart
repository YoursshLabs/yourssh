import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'hotkey_settings_screen.dart';
import 'settings_tiles.dart';

/// Settings → Keyboard: opens the shortcut editor ([HotkeySettingsScreen]).
class HotkeysSettingsSection extends StatelessWidget {
  const HotkeysSettingsSection({super.key});

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'Keyboard',
    tiles: [
      settingsRowTile(
        label: 'Keyboard Shortcuts',
        trailing: FButton(
          key: const ValueKey('settings-hotkeys-configure'),
          variant: .outline,
          size: .sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.keyboard),
          onPress: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HotkeySettingsScreen()),
          ),
          child: const Text('Configure'),
        ),
      ),
    ],
  );
}
