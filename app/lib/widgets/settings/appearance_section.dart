import 'package:flutter/material.dart';

import '../terminal_appearance_controls.dart';
import 'settings_tiles.dart';

/// Settings → Appearance: terminal colour theme, font size and font. The
/// controls are shared with the terminal side panel
/// ([TerminalAppearanceControls]) and lay out their own rows.
class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context) => const SettingsSection(
    title: 'Appearance',
    child: SettingsCard(
      child: TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
    ),
  );
}
