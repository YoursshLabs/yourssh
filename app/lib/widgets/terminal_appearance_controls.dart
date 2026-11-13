// app/lib/widgets/terminal_appearance_controls.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
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
  static const double _minSize = 10;
  static const double _maxSize = 24;

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

  double _sizeOf(FSliderValue v) =>
      (_minSize + v.max * (_maxSize - _minSize)).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final showCustom =
        _pendingCustom || !kBundledTerminalFonts.contains(settings.terminalFont);
    // Clamp: prefs may hold an out-of-range value.
    final size = settings.fontSize.clamp(_minSize, _maxSize).toDouble();
    // FSliderValue needs 0 < max <= 1.
    final fraction =
        ((size - _minSize) / (_maxSize - _minSize)).clamp(0.01, 1.0);

    // `inline` — compact control: in vertical layout it shares a row with the
    // label (right-aligned) instead of stacking below it.
    final entries = <(String, Widget, {bool inline})>[
      (
        'Color theme',
        ThemePickerButton(
          currentTheme: settings.terminalTheme,
          onChanged: (v) =>
              context.read<SettingsProvider>().save(terminalTheme: v),
        ),
        inline: true,
      ),
      (
        'Font size: ${settings.fontSize.round()}pt',
        SizedBox(
          width: _isRows ? 200 : double.infinity,
          child: FSlider(
            control: .liftedContinuous(
              value: FSliderValue(max: fraction),
              // Preview while dragging (no prefs write per tick); persist
              // once when the drag ends.
              onChange: (v) =>
                  context.read<SettingsProvider>().previewFontSize(_sizeOf(v)),
            ),
            // `onEnd`'s value can lag the lifted one, so persist what the
            // drag previewed.
            onEnd: (_) {
              final provider = context.read<SettingsProvider>();
              provider.save(fontSize: provider.fontSize);
            },
          ),
        ),
        inline: false,
      ),
      ('Terminal font', _buildFontSelect(context, settings), inline: false),
      if (showCustom)
        ('Custom font name', _buildCustomFontField(context), inline: false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, entry) in entries.indexed) ..._buildEntry(i, entry),
      ],
    );
  }

  List<Widget> _buildEntry(int index, (String, Widget, {bool inline}) entry) {
    final (label, control, inline: inline) = entry;
    const labelStyle = TextStyle(color: YsColors.foreground, fontSize: 13);
    final labelText =
        Text(label, style: labelStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (_isRows) {
      return [
        if (index > 0) const FDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: YsSpace.s4, vertical: YsSpace.s3),
          child: Row(
            children: [
              Expanded(child: labelText),
              control,
            ],
          ),
        ),
      ];
    }
    if (inline) {
      return [
        if (index > 0) const SizedBox(height: YsSpace.s4),
        Row(
          children: [
            Expanded(child: labelText),
            control,
          ],
        ),
      ];
    }
    return [
      if (index > 0) const SizedBox(height: YsSpace.s4),
      labelText,
      const SizedBox(height: YsSpace.s2 - 2),
      control,
    ];
  }

  /// Bundled fonts followed by a trailing "Custom…" entry; the select's value
  /// is the option index.
  Widget _buildFontSelect(BuildContext context, SettingsProvider settings) {
    final isCustom = !kBundledTerminalFonts.contains(settings.terminalFont);
    final customIndex = kBundledTerminalFonts.length;
    final index = (isCustom || _pendingCustom)
        ? customIndex
        : kBundledTerminalFonts.indexOf(settings.terminalFont);
    String nameOf(int i) => i == customIndex
        ? 'Custom…'
        : (kBundledTerminalFonts[i] == 'monospace'
            ? 'System Default'
            : kBundledTerminalFonts[i]);
    return SizedBox(
      width: _isRows ? 220 : double.infinity,
      child: FSelect<int>.rich(
        key: const Key('terminal-font-select'),
        control: .lifted(
          value: index,
          onChange: (i) {
            if (i == null) return;
            if (i == customIndex) {
              setState(() {
                _pendingCustom = true;
                _customFontController.clear();
              });
            } else {
              setState(() => _pendingCustom = false);
              context
                  .read<SettingsProvider>()
                  .save(terminalFont: kBundledTerminalFonts[i]);
            }
          },
        ),
        format: nameOf,
        children: [
          for (var i = 0; i <= customIndex; i++)
            FSelectItem<int>(
              value: i,
              // Render each option in its own typeface as a live preview.
              title: Text(
                nameOf(i),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: i == customIndex ? null : kBundledTerminalFonts[i],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomFontField(BuildContext context) {
    return SizedBox(
      width: _isRows ? 260 : double.infinity,
      child: Row(
        children: [
          Expanded(
            child: FTextField(
              key: const Key('custom-font-field'),
              control:
                  FTextFieldControl.managed(controller: _customFontController),
              size: .sm,
              hint: 'e.g. Hack Nerd Font',
            ),
          ),
          const SizedBox(width: YsSpace.s2 - 2),
          FButton(
            variant: .ghost,
            size: .sm,
            mainAxisSize: MainAxisSize.min,
            onPress: () {
              final name = _customFontController.text.trim();
              if (name.isEmpty) return;
              setState(() => _pendingCustom = false);
              context.read<SettingsProvider>().save(terminalFont: name);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}
