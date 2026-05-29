// app/lib/widgets/hotkey_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class HotkeySettingsScreen extends StatelessWidget {
  const HotkeySettingsScreen({super.key});

  static const _labels = {
    'new_session': 'New Session',
    'close_session': 'Close Session',
    'next_session': 'Next Session',
    'prev_session': 'Previous Session',
    'toggle_input_bar': 'Toggle Input Bar',
    'split_horizontal': 'Split Horizontal',
    'split_vertical': 'Split Vertical',
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Keyboard Shortcuts'),
        backgroundColor: const Color(0xFF141414),
      ),
      body: ListView(
        children: _labels.entries.map((entry) {
          final current = settings.hotkeys[entry.key] ?? '';
          return ListTile(
            title: Text(entry.value, style: const TextStyle(color: Color(0xFFD4D4D4))),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                border: Border.all(color: const Color(0xFF2A2A2A)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                current,
                style: const TextStyle(
                  color: Color(0xFF22C55E),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
