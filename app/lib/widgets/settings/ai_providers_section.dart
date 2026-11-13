import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/ai_provider_config.dart';
import '../../providers/ai_chat_provider.dart';
import '../../theme/app_theme.dart';
import 'settings_tiles.dart';

/// Settings → AI providers: one tile per provider with its API key
/// (obscured, with a show/hide toggle) and model.
class AiProvidersSettingsSection extends StatefulWidget {
  const AiProvidersSettingsSection({super.key});

  @override
  State<AiProvidersSettingsSection> createState() =>
      _AiProvidersSettingsSectionState();
}

class _AiProvidersSettingsSectionState
    extends State<AiProvidersSettingsSection> {
  final _controllers = <AiProvider, TextEditingController>{};
  final _focusNodes = <AiProvider, FocusNode>{};
  final _showKey = <AiProvider, bool>{};

  @override
  void initState() {
    super.initState();
    for (final p in AiProvider.values) {
      _controllers[p] = TextEditingController();
      _showKey[p] = false;
      final node = FocusNode();
      node.addListener(() {
        if (!node.hasFocus && mounted) _saveKey(p);
      });
      _focusNodes[p] = node;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configs = context.read<AiChatProvider>().configs;
    for (final p in AiProvider.values) {
      if (_controllers[p]!.text.isEmpty && configs[p] != null) {
        _controllers[p]!.text = configs[p]!.apiKey;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _saveKey(AiProvider p) async {
    final key = _controllers[p]!.text.trim();
    if (key.isEmpty) return;
    final ai = context.read<AiChatProvider>();
    await ai.setProviderConfig(p, apiKey: key);
    final err = ai.lastError;
    if (err == null) return;
    // Clear even when unmounted so the stale error is not shown later.
    ai.clearError();
    if (!mounted) return;
    AppSnack.info(context, err);
  }

  String _label(AiProvider p) => switch (p) {
    AiProvider.anthropic => 'Anthropic',
    AiProvider.openai => 'OpenAI',
    AiProvider.gemini => 'Google Gemini',
  };

  String _hint(AiProvider p) => switch (p) {
    AiProvider.anthropic => 'sk-ant-...',
    AiProvider.openai => 'sk-...',
    AiProvider.gemini => 'AIza...',
  };

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiChatProvider>();
    return SettingsSection(
      title: 'AI providers',
      tiles: [
        for (final p in AiProvider.values)
          settingsContentTile(child: _buildProvider(context, ai, p)),
      ],
    );
  }

  Widget _buildProvider(BuildContext context, AiChatProvider ai, AiProvider p) {
    final config = ai.configs[p];
    final models = AiChatProvider.presetModels[p]!;
    final selectedModel = config?.model ?? models.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _label(p),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (config != null)
              const Icon(
                FLucideIcons.circleCheck,
                size: 14,
                color: AppColors.success,
                semanticLabel: 'Configured',
              ),
          ],
        ),
        const SizedBox(height: YsSpace.s2),
        FTextField.password(
          key: ValueKey('ai-key-${p.name}'),
          control: .managed(controller: _controllers[p]),
          focusNode: _focusNodes[p],
          obscureTextControl: .lifted(
            value: !_showKey[p]!,
            onChange: (obscured) => setState(() => _showKey[p] = !obscured),
          ),
          size: .sm,
          label: null,
          hint: _hint(p),
          autofillHints: const [],
          textInputAction: TextInputAction.done,
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
          onSubmit: (_) => _saveKey(p),
          suffixBuilder: (context, style, obscure, variants) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: obscure.value ? 'Show API key' : 'Hide API key',
                excludeFromSemantics: true,
                child: FTextField.defaultObscureIconBuilder(
                  context,
                  style,
                  obscure,
                  variants,
                ),
              ),
              if (config != null)
                SettingsIconButton(
                  icon: FLucideIcons.x,
                  tooltip: 'Clear API key',
                  onPress: () {
                    _controllers[p]!.clear();
                    context.read<AiChatProvider>().clearProviderConfig(p);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: YsSpace.s2),
        SettingsRow(
          label: 'Model',
          trailing: SettingsSelect<String>(
            key: ValueKey('ai-model-${p.name}'),
            value: selectedModel,
            width: 240,
            options: [for (final m in models) (m, m)],
            onChanged: (v) =>
                context.read<AiChatProvider>().setProviderConfig(p, model: v),
          ),
        ),
      ],
    );
  }
}
