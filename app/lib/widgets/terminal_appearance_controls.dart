// app/lib/widgets/terminal_appearance_controls.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'theme_picker.dart';

/// How [TerminalAppearanceControls] lays out each control.
enum AppearanceControlsLayout {
  /// Label left, control right — Settings screen style.
  rows,

  /// Label above control — for the narrow side panel.
  vertical,
}

/// Fonts bundled with the app, selectable without typing a name.
const kBundledTerminalFonts = [
  'monospace',
  'MesloLGS NF',
  'DejaVu Sans Mono for Powerline',
  'Inconsolata for Powerline',
  'Meslo LG S for Powerline',
  'Source Code Pro for Powerline',
  'Ubuntu Mono derivative Powerline',
  'Roboto Mono for Powerline',
];

const _kCustom = '__custom__';

/// Terminal appearance settings (color theme, font size, font family),
/// shared between the Settings screen and the terminal config side panel.
/// Reads and writes [SettingsProvider] directly.
class TerminalAppearanceControls extends StatefulWidget {
  final AppearanceControlsLayout layout;

  const TerminalAppearanceControls({super.key, required this.layout});

  @override
  State<TerminalAppearanceControls> createState() =>
      _TerminalAppearanceControlsState();
}

class _TerminalAppearanceControlsState
    extends State<TerminalAppearanceControls> {
  final _customFontController = TextEditingController();
  bool _pendingCustom = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final font = context.read<SettingsProvider>().terminalFont;
    final isCustom = !kBundledTerminalFonts.contains(font);
    if (isCustom && _customFontController.text.isEmpty) {
      _customFontController.text = font;
    }
  }

  @override
  void dispose() {
    _customFontController.dispose();
    super.dispose();
  }

  bool get _isRows => widget.layout == AppearanceControlsLayout.rows;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final showCustom =
        _pendingCustom || !kBundledTerminalFonts.contains(settings.terminalFont);

    final entries = <(String, Widget)>[
      (
        'Color theme',
        ThemePickerButton(
          currentTheme: settings.terminalTheme,
          onChanged: (v) =>
              context.read<SettingsProvider>().save(terminalTheme: v),
        ),
      ),
      (
        'Font size: ${settings.fontSize.round()}pt',
        SizedBox(
          width: _isRows ? 200 : double.infinity,
          child: Slider(
            // Clamp: prefs may hold an out-of-range value (Slider asserts).
            value: settings.fontSize.clamp(10, 24).toDouble(),
            min: 10,
            max: 24,
            divisions: 14,
            // Preview while dragging (no prefs write per tick); persist once
            // when the drag ends.
            onChanged: (v) =>
                context.read<SettingsProvider>().previewFontSize(v),
            onChangeEnd: (v) =>
                context.read<SettingsProvider>().save(fontSize: v),
          ),
        ),
      ),
      ('Terminal font', _buildFontDropdown(context, settings)),
      if (showCustom) ('Custom font name', _buildCustomFontField(context)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, entry) in entries.indexed) ..._buildEntry(i, entry),
      ],
    );
  }

  List<Widget> _buildEntry(int index, (String, Widget) entry) {
    final (label, control) = entry;
    if (_isRows) {
      return [
        if (index > 0)
          const Divider(height: 1, color: AppColors.border, indent: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
              ),
              control,
            ],
          ),
        ),
      ];
    }
    return [
      if (index > 0) const SizedBox(height: 16),
      Text(label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      const SizedBox(height: 6),
      control,
    ];
  }

  Widget _buildFontDropdown(BuildContext context, SettingsProvider settings) {
    final isCustom = !kBundledTerminalFonts.contains(settings.terminalFont);
    final ddValue =
        (isCustom || _pendingCustom) ? _kCustom : settings.terminalFont;
    return DropdownButton<String>(
      value: ddValue,
      isExpanded: !_isRows,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: [
        ...kBundledTerminalFonts.map((f) => DropdownMenuItem(
              value: f,
              child: Text(f == 'monospace' ? 'System Default' : f,
                  style: const TextStyle(fontSize: 12)),
            )),
        const DropdownMenuItem(
          value: _kCustom,
          child: Text('Custom…', style: TextStyle(fontSize: 12)),
        ),
      ],
      onChanged: (v) {
        if (v == _kCustom) {
          setState(() {
            _pendingCustom = true;
            _customFontController.clear();
          });
        } else if (v != null) {
          setState(() => _pendingCustom = false);
          context.read<SettingsProvider>().save(terminalFont: v);
        }
      },
    );
  }

  Widget _buildCustomFontField(BuildContext context) {
    return SizedBox(
      width: _isRows ? 220 : double.infinity,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _customFontController,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'e.g. Hack Nerd Font',
                hintStyle: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 12),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () {
              final name = _customFontController.text.trim();
              if (name.isEmpty) return;
              setState(() => _pendingCustom = false);
              context.read<SettingsProvider>().save(terminalFont: name);
            },
            child: const Text('Apply', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
