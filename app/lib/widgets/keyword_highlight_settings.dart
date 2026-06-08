import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/keyword_highlight_rule.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

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

class KeywordHighlightSection extends StatelessWidget {
  const KeywordHighlightSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('Enable keyword highlighting',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text(
              'Tint matching text in all terminal sessions',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: settings.keywordHighlightingEnabled,
          onChanged: (v) => context
              .read<SettingsProvider>()
              .save(keywordHighlightingEnabled: v),
        ),
        const Divider(height: 1, color: AppColors.border, indent: 16),
        ...settings.keywordHighlightRules.asMap().entries.map((entry) {
          final i = entry.key;
          final rule = entry.value;
          return Column(
            children: [
              _RuleRow(
                rule: rule,
                onToggle: (enabled) {
                  final updated = List<AppKeywordHighlightRule>.from(
                      settings.keywordHighlightRules);
                  updated[i] = rule.copyWith(enabled: enabled);
                  context
                      .read<SettingsProvider>()
                      .save(keywordHighlightRules: updated);
                },
                onEdit: () => _showRuleDialog(context, settings, rule: rule, index: i),
                onDelete: () {
                  final updated = List<AppKeywordHighlightRule>.from(
                      settings.keywordHighlightRules)
                    ..removeAt(i);
                  context
                      .read<SettingsProvider>()
                      .save(keywordHighlightRules: updated);
                },
              ),
              if (i < settings.keywordHighlightRules.length - 1)
                const Divider(height: 1, color: AppColors.border, indent: 16),
            ],
          );
        }),
        if (settings.keywordHighlightRules.length < kMaxKeywordHighlightRules)
          Column(
            children: [
              const Divider(height: 1, color: AppColors.border, indent: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.add, color: AppColors.accent, size: 18),
                title: const Text('Add rule',
                    style: TextStyle(color: AppColors.accent, fontSize: 13)),
                onTap: () => _showRuleDialog(context, settings),
              ),
            ],
          ),
        if (settings.keywordHighlightRules.length >= kMaxKeywordHighlightRules)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Maximum $kMaxKeywordHighlightRules rules reached.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Future<void> _showRuleDialog(
    BuildContext context,
    SettingsProvider settings, {
    AppKeywordHighlightRule? rule,
    int? index,
  }) async {
    final result = await showDialog<AppKeywordHighlightRule>(
      context: context,
      builder: (_) => _KeywordRuleDialog(initial: rule),
    );
    if (result == null || !context.mounted) return;
    final current = context.read<SettingsProvider>();
    final updated = List<AppKeywordHighlightRule>.from(current.keywordHighlightRules);
    if (index != null) {
      if (index < updated.length) updated[index] = result;
    } else {
      if (updated.length < kMaxKeywordHighlightRules) updated.add(result);
    }
    current.save(keywordHighlightRules: updated);
  }
}

class _RuleRow extends StatelessWidget {
  final AppKeywordHighlightRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleRow({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rule.background != null)
            _ColorDot(color: rule.background!, label: 'bg'),
          if (rule.foreground != null) ...[
            if (rule.background != null) const SizedBox(width: 4),
            _ColorDot(color: rule.foreground!, label: 'fg', border: true),
          ],
        ],
      ),
      title: Text(rule.label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      subtitle: Text(
        '${rule.isRegex ? "regex" : "literal"}  ·  ${rule.pattern}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: rule.enabled,
            onChanged: onToggle,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
            onPressed: onEdit,
            tooltip: 'Edit rule',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textSecondary),
            onPressed: onDelete,
            tooltip: 'Delete rule',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;

  const _ColorDot({required this.color, required this.label, this.border = false});

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
              ? Border.all(color: AppColors.textSecondary, width: 1.5)
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
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(
        widget.initial == null ? 'Add rule' : 'Edit rule',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Label', _labelCtrl, hint: 'e.g. Error'),
            const SizedBox(height: 12),
            _field(
              'Pattern',
              _patternCtrl,
              hint: _isRegex ? r'e.g. \berror\b' : 'e.g. error',
              monospace: true,
              onChanged: (_) => _validatePattern(),
              errorText: _regexError,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _isRegex,
                  onChanged: (v) =>
                      setState(() => _isRegex = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('Regex',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                const SizedBox(width: 16),
                Checkbox(
                  value: _caseSensitive,
                  onChanged: (v) =>
                      setState(() => _caseSensitive = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('Case-sensitive',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            _ColorPickerButton(
              label: 'Foreground (text color)',
              current: _foreground,
              presets: _kForegroundPresets,
              onChanged: (c) => setState(() => _foreground = c),
            ),
            const SizedBox(height: 8),
            _ColorPickerButton(
              label: 'Background',
              current: _background,
              presets: _kBackgroundPresets,
              onChanged: (c) => setState(() => _background = c),
            ),
            if (!_isValid && _labelCtrl.text.isNotEmpty && _patternCtrl.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Choose at least one color.',
                  style: TextStyle(color: Colors.red, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isValid
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

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool monospace = false,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontFamily: monospace ? 'monospace' : null,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            errorText: errorText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorPickerButton extends StatelessWidget {
  final String label;
  final Color? current;
  final List<Color> presets;
  final ValueChanged<Color?> onChanged;

  const _ColorPickerButton({
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
          child: Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        GestureDetector(
          onTap: () => _pick(context),
          child: Container(
            width: 80,
            height: 28,
            decoration: BoxDecoration(
              color: current ?? Colors.transparent,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: current == null
                ? const Text('None',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11))
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showDialog<Color?>(
      context: context,
      builder: (_) => _ColorGridDialog(presets: presets, current: current),
    );
    if (result == _clearSentinel) {
      onChanged(null);
    } else if (result != null) {
      onChanged(result);
    }
  }
}

final _clearSentinel = const Color(0x00000000);

class _ColorGridDialog extends StatelessWidget {
  final List<Color> presets;
  final Color? current;
  const _ColorGridDialog({required this.presets, required this.current});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('Pick color',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context, _clearSentinel),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: const Text('✕',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ),
          ...presets.map((c) => GestureDetector(
                onTap: () => Navigator.pop(context, c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                    border: current == c
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
