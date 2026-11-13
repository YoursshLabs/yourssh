import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/keyword_highlight_rule.dart';
import '../../providers/settings_provider.dart';
import 'settings_tiles.dart';

const _kForegroundPresets = [
  Color(0xFFEF9A9A),
  Color(0xFFFFCC80),
  Color(0xFFFFF176),
  Color(0xFFA5D6A7),
  Color(0xFF80DEEA),
  Color(0xFF90CAF9),
  Color(0xFFCE93D8),
  Color(0xFFFFFFFF),
  Color(0xFF9E9E9E),
  Color(0xFFBDBDBD),
];

const _kBackgroundPresets = [
  Color(0xFFB71C1C),
  Color(0xFFE65100),
  Color(0xFFF57F17),
  Color(0xFF1B5E20),
  Color(0xFF006064),
  Color(0xFF0D47A1),
  Color(0xFF4A148C),
  Color(0xFF37474F),
];

const _monoSubtitle = TextStyle(
  fontFamily: kYsMonoFontFamily,
  fontFamilyFallback: kYsMonoFontFallback,
  fontSize: 11,
);

/// Settings → Keyword highlighting: the master switch and the rule list
/// (enable, edit, delete, add — capped at [kMaxKeywordHighlightRules]).
class KeywordHighlightSection extends StatelessWidget {
  const KeywordHighlightSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final rules = settings.keywordHighlightRules;
    SettingsProvider write() => context.read<SettingsProvider>();

    void saveRules(List<AppKeywordHighlightRule> updated) =>
        write().save(keywordHighlightRules: updated);

    return SettingsSection(
      title: 'Keyword highlighting',
      tiles: [
        settingsSwitchTile(
          key: const ValueKey('settings-keyword-enable'),
          label: 'Enable keyword highlighting',
          description: 'Tint matching text in all terminal sessions',
          value: settings.keywordHighlightingEnabled,
          onChange: (v) => write().save(keywordHighlightingEnabled: v),
        ),
        for (final (i, rule) in rules.indexed)
          _ruleTile(
            index: i,
            rule: rule,
            onToggle: (enabled) {
              final updated = List<AppKeywordHighlightRule>.from(rules);
              updated[i] = rule.copyWith(enabled: enabled);
              saveRules(updated);
            },
            onEdit: () => _showRuleDialog(context, rule: rule, index: i),
            onDelete: () {
              final updated = List<AppKeywordHighlightRule>.from(rules)
                ..removeAt(i);
              saveRules(updated);
            },
          ),
        if (rules.length < kMaxKeywordHighlightRules)
          FTile(
            key: const ValueKey('keyword-add-rule'),
            prefix: const Icon(FLucideIcons.plus),
            title: const Text('Add rule'),
            onPress: () => _showRuleDialog(context),
          )
        else
          settingsContentTile(
            child: Text(
              'Maximum $kMaxKeywordHighlightRules rules reached.',
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  FTile _ruleTile({
    required int index,
    required AppKeywordHighlightRule rule,
    required ValueChanged<bool> onToggle,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return settingsContentTile(
      key: ValueKey('keyword-rule-$index'),
      child: Row(
        children: [
          if (rule.background != null)
            _ColorDot(color: rule.background!, label: 'bg'),
          if (rule.foreground != null) ...[
            if (rule.background != null) const SizedBox(width: 4),
            _ColorDot(color: rule.foreground!, label: 'fg', border: true),
          ],
          const SizedBox(width: YsSpace.s3),
          Expanded(
            child: SettingsRow(
              label: rule.label,
              descriptionWidget: Text(
                '${rule.isRegex ? "regex" : "literal"}  ·  ${rule.pattern}',
                style: _monoSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FSwitch(
                    key: ValueKey('keyword-rule-switch-$index'),
                    value: rule.enabled,
                    semanticsLabel: 'Enable ${rule.label}',
                    onChange: onToggle,
                  ),
                  const SizedBox(width: YsSpace.s1),
                  SettingsIconButton(
                    key: ValueKey('keyword-rule-edit-$index'),
                    icon: FLucideIcons.pencil,
                    tooltip: 'Edit rule',
                    onPress: onEdit,
                  ),
                  SettingsIconButton(
                    key: ValueKey('keyword-rule-delete-$index'),
                    icon: FLucideIcons.trash2,
                    tooltip: 'Delete rule',
                    onPress: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRuleDialog(
    BuildContext context, {
    AppKeywordHighlightRule? rule,
    int? index,
  }) async {
    final result = await showYsDialog<AppKeywordHighlightRule>(
      context,
      builder: (_) => _KeywordRuleDialog(initial: rule),
    );
    if (result == null || !context.mounted) return;
    final current = context.read<SettingsProvider>();
    final updated = List<AppKeywordHighlightRule>.from(
      current.keywordHighlightRules,
    );
    if (index != null) {
      if (index < updated.length) updated[index] = result;
    } else {
      if (updated.length < kMaxKeywordHighlightRules) updated.add(result);
    }
    current.save(keywordHighlightRules: updated);
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;

  const _ColorDot({
    required this.color,
    required this.label,
    this.border = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border
              ? Border.all(color: YsColors.mutedForeground, width: 1.5)
              : null,
        ),
      ),
    );
  }
}

class _KeywordRuleDialog extends StatefulWidget {
  final AppKeywordHighlightRule? initial;
  const _KeywordRuleDialog({this.initial});

  @override
  State<_KeywordRuleDialog> createState() => _KeywordRuleDialogState();
}

class _KeywordRuleDialogState extends State<_KeywordRuleDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _patternCtrl;
  late bool _isRegex;
  late bool _caseSensitive;
  Color? _foreground;
  Color? _background;
  String? _regexError;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _labelCtrl = TextEditingController(text: r?.label ?? '');
    _patternCtrl = TextEditingController(text: r?.pattern ?? '');
    _isRegex = r?.isRegex ?? false;
    _caseSensitive = r?.caseSensitive ?? false;
    _foreground = r?.foreground;
    _background = r?.background;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _patternCtrl.dispose();
    super.dispose();
  }

  void _validatePattern() {
    if (!_isRegex) {
      setState(() => _regexError = null);
      return;
    }
    try {
      RegExp(_patternCtrl.text);
      setState(() => _regexError = null);
    } catch (e) {
      setState(() => _regexError = e.toString());
    }
  }

  bool get _isValid =>
      _labelCtrl.text.trim().isNotEmpty &&
      _patternCtrl.text.isNotEmpty &&
      _regexError == null &&
      (_foreground != null || _background != null);

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: widget.initial == null ? 'Add rule' : 'Edit rule',
      body: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextField(
              key: const ValueKey('keyword-rule-label'),
              control: .managed(
                controller: _labelCtrl,
                // Rebuild so Save and the colour notice track the input.
                onChange: (_) => setState(() {}),
              ),
              label: const Text('Label'),
              hint: 'e.g. Error',
            ),
            const SizedBox(height: YsSpace.s3),
            FTextField(
              key: const ValueKey('keyword-rule-pattern'),
              control: .managed(
                controller: _patternCtrl,
                onChange: (_) => _validatePattern(),
              ),
              label: const Text('Pattern'),
              hint: _isRegex ? r'e.g. \berror\b' : 'e.g. error',
              autocorrect: false,
              enableSuggestions: false,
              error: _regexError == null ? null : Text(_regexError!),
              style: .delta(
                contentTextStyle: .delta([
                  .base(
                    const .delta(
                      fontFamily: kYsMonoFontFamily,
                      fontFamilyFallback: kYsMonoFontFallback,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: YsSpace.s3),
            Wrap(
              spacing: YsSpace.s4,
              runSpacing: YsSpace.s2,
              children: [
                FCheckbox(
                  key: const ValueKey('keyword-rule-regex'),
                  value: _isRegex,
                  onChange: (v) => setState(() => _isRegex = v),
                  label: const Text('Regex'),
                ),
                FCheckbox(
                  key: const ValueKey('keyword-rule-case'),
                  value: _caseSensitive,
                  onChange: (v) => setState(() => _caseSensitive = v),
                  label: const Text('Case-sensitive'),
                ),
              ],
            ),
            const SizedBox(height: YsSpace.s3),
            _ColorPickerButton(
              swatchKey: const ValueKey('keyword-rule-fg'),
              label: 'Foreground (text color)',
              current: _foreground,
              presets: _kForegroundPresets,
              onChanged: (c) => setState(() => _foreground = c),
            ),
            const SizedBox(height: YsSpace.s2),
            _ColorPickerButton(
              swatchKey: const ValueKey('keyword-rule-bg'),
              label: 'Background',
              current: _background,
              presets: _kBackgroundPresets,
              onChanged: (c) => setState(() => _background = c),
            ),
            if (!_isValid &&
                _labelCtrl.text.isNotEmpty &&
                _patternCtrl.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: YsSpace.s2),
                child: Text(
                  'Choose at least one color.',
                  style: TextStyle(color: YsColors.error, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FButton(
          variant: .outline,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          key: const ValueKey('keyword-rule-save'),
          onPress: _isValid
              ? () {
                  Navigator.pop(
                    context,
                    AppKeywordHighlightRule(
                      id: widget.initial?.id,
                      label: _labelCtrl.text.trim(),
                      pattern: _patternCtrl.text,
                      isRegex: _isRegex,
                      caseSensitive: _caseSensitive,
                      enabled: widget.initial?.enabled ?? true,
                      foreground: _foreground,
                      background: _background,
                    ),
                  );
                }
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A colour swatch; opens [_ColorGridDialog] to pick or clear the colour.
class _ColorPickerButton extends StatelessWidget {
  final Key swatchKey;
  final String label;
  final Color? current;
  final List<Color> presets;
  final ValueChanged<Color?> onChanged;

  const _ColorPickerButton({
    required this.swatchKey,
    required this.label,
    required this.current,
    required this.presets,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: YsColors.mutedForeground,
              fontSize: 12,
            ),
          ),
        ),
        FTappable(
          key: swatchKey,
          semanticsLabel: label,
          onPress: () => _pick(context),
          builder: (context, variants, child) => Container(
            width: 80,
            height: 28,
            decoration: BoxDecoration(
              color: current ?? Colors.transparent,
              border: Border.all(
                color:
                    variants.contains(FTappableVariant.focused) ||
                        variants.contains(FTappableVariant.hovered)
                    ? YsColors.primary
                    : YsColors.border,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: child,
          ),
          child: current == null
              ? const Text(
                  'None',
                  style: TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 11,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showYsDialog<Color?>(
      context,
      builder: (_) => _ColorGridDialog(presets: presets, current: current),
    );
    if (result == _clearSentinel) {
      onChanged(null);
    } else if (result != null) {
      onChanged(result);
    }
  }
}

const _clearSentinel = Color(0x00000000);

class _ColorGridDialog extends StatelessWidget {
  final List<Color> presets;
  final Color? current;
  const _ColorGridDialog({required this.presets, required this.current});

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: 'Pick color',
      body: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Tooltip(
            message: 'None',
            excludeFromSemantics: true,
            child: _swatch(
              context,
              key: const ValueKey('keyword-color-none'),
              semanticsLabel: 'None',
              result: _clearSentinel,
              child: const Text(
                '✕',
                style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
              ),
            ),
          ),
          for (final (i, c) in presets.indexed)
            _swatch(
              context,
              key: ValueKey('keyword-color-$i'),
              semanticsLabel:
                  '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              result: c,
              color: c,
              selected: current == c,
            ),
        ],
      ),
    );
  }

  Widget _swatch(
    BuildContext context, {
    required Key key,
    required String semanticsLabel,
    required Color result,
    Color? color,
    bool selected = false,
    Widget? child,
  }) {
    return FTappable(
      key: key,
      semanticsLabel: semanticsLabel,
      onPress: () => Navigator.pop(context, result),
      builder: (context, variants, child) {
        final focused = variants.contains(FTappableVariant.focused);
        return Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: selected || focused
                ? Border.all(
                    color: focused ? YsColors.primary : Colors.white,
                    width: 2,
                  )
                : color == null
                ? Border.all(color: YsColors.border)
                : null,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
