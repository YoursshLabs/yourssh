import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _themes = ['Dracula', 'One Dark', 'Tokyo Night', 'Nord', 'Solarized Dark'];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.sidebar,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Text('Settings', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _Section(title: 'Connection', children: [
                  _Row(
                    label: 'Auto-reconnect',
                    subtitle: 'Reconnect when connection drops',
                    trailing: Switch(
                      value: settings.autoReconnect,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => context.read<SettingsProvider>().save(autoReconnect: v),
                    ),
                  ),
                  _Row(
                    label: 'Max reconnect attempts',
                    trailing: _DropDown<int>(
                      value: settings.reconnectAttempts,
                      items: [1, 3, 5, 10],
                      labelOf: (n) => '$n times',
                      onChanged: (v) => context.read<SettingsProvider>().save(reconnectAttempts: v),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: 'Terminal', children: [
                  _Row(
                    label: 'Color theme',
                    trailing: _DropDown<String>(
                      value: settings.terminalTheme,
                      items: _themes,
                      labelOf: (t) => t,
                      onChanged: (v) => context.read<SettingsProvider>().save(terminalTheme: v),
                    ),
                  ),
                  _Row(
                    label: 'Font size: ${settings.fontSize.round()}pt',
                    trailing: SizedBox(
                      width: 200,
                      child: Slider(
                        value: settings.fontSize,
                        min: 10,
                        max: 24,
                        divisions: 14,
                        onChanged: (v) => context.read<SettingsProvider>().save(fontSize: v),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _Section(title: 'About', children: [
                  const _Row(label: 'Version', trailing: Text('v0.1.0', style: TextStyle(color: AppColors.textTertiary, fontSize: 12))),
                  const _Row(label: 'Build', trailing: Text('Flutter + dartssh2', style: TextStyle(color: AppColors.textTertiary, fontSize: 12))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: children.indexed.map((e) {
              final (i, child) = e;
              return Column(children: [
                child,
                if (i < children.length - 1)
                  const Divider(height: 1, color: AppColors.border, indent: 16),
              ]);
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? trailing;
  const _Row({required this.label, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _DropDown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final void Function(T) onChanged;
  const _DropDown({required this.value, required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(labelOf(i)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}
