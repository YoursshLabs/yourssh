# AI Multi-Provider Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Anthropic, OpenAI, and Google Gemini support to the AI chat feature, with API key + model config in Settings and a provider picker in the chat sidebar.

**Architecture:** New `AiProviderConfig` model holds apiKey+model per provider. `AiChatProvider` is rewritten to hold a map of configs and dispatch `send()` to the correct API. Settings screen gets an `_AiProvidersSection` widget. The chat sidebar header gets a provider dropdown.

**Tech Stack:** Flutter, Dart, `http`, `flutter_secure_storage`, `shared_preferences`, `flutter_test`

---

## File Map

| File | Action |
|------|--------|
| `app/lib/models/ai_provider_config.dart` | **Create** — `AiProvider` enum + `AiProviderConfig` model |
| `app/lib/providers/ai_chat_provider.dart` | **Rewrite** — multi-provider logic |
| `app/test/providers/ai_chat_provider_test.dart` | **Create** — unit tests |
| `app/lib/widgets/settings_screen.dart` | **Modify** — add `_AiProvidersSection` |
| `app/lib/widgets/ai_chat_sidebar.dart` | **Modify** — provider dropdown in header, replace inline key prompt |

---

### Task 1: Create `AiProviderConfig` model

**Files:**
- Create: `app/lib/models/ai_provider_config.dart`

- [ ] **Step 1: Create the file**

```dart
// app/lib/models/ai_provider_config.dart

enum AiProvider { anthropic, openai, gemini }

class AiProviderConfig {
  final String apiKey;
  final String model;

  const AiProviderConfig({required this.apiKey, required this.model});
}
```

- [ ] **Step 2: Run analyze to verify no errors**

```bash
cd app && flutter analyze lib/models/ai_provider_config.dart
```

Expected: no issues found.

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/ai_provider_config.dart
git commit -m "feat: add AiProvider enum and AiProviderConfig model"
```

---

### Task 2: Write failing tests for `AiChatProvider`

**Files:**
- Create: `app/test/providers/ai_chat_provider_test.dart`

- [ ] **Step 1: Create the test file**

```dart
// app/test/providers/ai_chat_provider_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ai_provider_config.dart';
import 'package:yourssh/providers/ai_chat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> secureStore = {};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'write':
          final key = call.arguments['key'] as String;
          final value = call.arguments['value'] as String?;
          if (value != null) secureStore[key] = value;
          return null;
        case 'read':
          final key = call.arguments['key'] as String;
          return secureStore[key];
        case 'delete':
          final key = call.arguments['key'] as String;
          secureStore.remove(key);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AiChatProvider', () {
    late AiChatProvider provider;

    setUp(() {
      provider = AiChatProvider();
    });

    tearDown(() => provider.dispose());

    test('starts unconfigured with no configs', () async {
      await Future.delayed(Duration.zero);
      expect(provider.configured, isFalse);
      expect(provider.configuredProviders, isEmpty);
      expect(provider.activeProvider, AiProvider.anthropic);
    });

    test('setProviderConfig stores key and uses default model', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.anthropic, apiKey: 'sk-ant-test');
      expect(provider.configured, isTrue);
      expect(provider.configs[AiProvider.anthropic]?.apiKey, 'sk-ant-test');
      expect(provider.configs[AiProvider.anthropic]?.model,
          AiChatProvider.presetModels[AiProvider.anthropic]!.first);
    });

    test('setProviderConfig updates model without changing key', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-test');
      await provider.setProviderConfig(AiProvider.openai, model: 'gpt-4o');
      expect(provider.configs[AiProvider.openai]?.model, 'gpt-4o');
      expect(provider.configs[AiProvider.openai]?.apiKey, 'sk-test');
    });

    test('clearProviderConfig removes config', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-test');
      await provider.clearProviderConfig(AiProvider.openai);
      expect(provider.configs[AiProvider.openai], isNull);
      expect(provider.configuredProviders, isNot(contains(AiProvider.openai)));
    });

    test('configuredProviders returns only providers with keys', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.anthropic, apiKey: 'sk-ant');
      await provider.setProviderConfig(AiProvider.gemini, apiKey: 'AIza-test');
      expect(provider.configuredProviders,
          containsAll([AiProvider.anthropic, AiProvider.gemini]));
      expect(provider.configuredProviders,
          isNot(contains(AiProvider.openai)));
    });

    test('setActiveProvider changes active provider', () async {
      await Future.delayed(Duration.zero);
      await provider.setActiveProvider(AiProvider.openai);
      expect(provider.activeProvider, AiProvider.openai);
    });

    test('clearProviderConfig on active provider switches to next configured', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.anthropic, apiKey: 'sk-ant');
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-oai');
      await provider.setActiveProvider(AiProvider.anthropic);
      await provider.clearProviderConfig(AiProvider.anthropic);
      expect(provider.activeProvider, AiProvider.openai);
    });

    test('clearProviderConfig on last provider sets active to anthropic', () async {
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-oai');
      await provider.setActiveProvider(AiProvider.openai);
      await provider.clearProviderConfig(AiProvider.openai);
      expect(provider.activeProvider, AiProvider.anthropic);
      expect(provider.configured, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/providers/ai_chat_provider_test.dart
```

Expected: compile error or runtime failures — `AiChatProvider` doesn't have `configs`, `configuredProviders`, `setProviderConfig`, `clearProviderConfig`, `setActiveProvider`, or `presetModels`.

---

### Task 3: Rewrite `AiChatProvider`

**Files:**
- Modify: `app/lib/providers/ai_chat_provider.dart`

- [ ] **Step 1: Replace the entire file**

```dart
// app/lib/providers/ai_chat_provider.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_provider_config.dart';
import '../models/chat_message.dart';

class AiChatProvider extends ChangeNotifier {
  static const _systemPrompt =
      'You are an SSH command assistant embedded in an SSH client app. '
      'Help the user with shell commands, explain error messages, suggest fixes, and assist with DevOps tasks. '
      'Keep responses concise and practical. Use code blocks for commands.';

  static const _activeProviderPrefKey = 'ai_active_provider';

  static const Map<AiProvider, List<String>> presetModels = {
    AiProvider.anthropic: [
      'claude-haiku-4-5-20251001',
      'claude-sonnet-4-6',
      'claude-opus-4-7',
    ],
    AiProvider.openai: ['gpt-4o-mini', 'gpt-4o', 'o1-mini'],
    AiProvider.gemini: [
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
    ],
  };

  final FlutterSecureStorage _storage;
  final Map<AiProvider, AiProviderConfig> _configs = {};
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  AiProvider _activeProvider = AiProvider.anthropic;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  Map<AiProvider, AiProviderConfig> get configs => Map.unmodifiable(_configs);
  AiProvider get activeProvider => _activeProvider;
  bool get configured => _configs[_activeProvider]?.apiKey.isNotEmpty == true;
  List<AiProvider> get configuredProviders => AiProvider.values
      .where((p) => _configs[p]?.apiKey.isNotEmpty == true)
      .toList();

  AiChatProvider({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final providerName = prefs.getString(_activeProviderPrefKey);
    if (providerName != null) {
      _activeProvider = AiProvider.values.firstWhere(
        (p) => p.name == providerName,
        orElse: () => AiProvider.anthropic,
      );
    }

    // Migrate legacy single Anthropic key
    final legacyKey = await _storage.read(key: 'ai_api_key');
    if (legacyKey != null && legacyKey.isNotEmpty) {
      await _storage.write(key: 'ai_config_anthropic_key', value: legacyKey);
      await _storage.delete(key: 'ai_api_key');
    }

    for (final p in AiProvider.values) {
      final key = await _storage.read(key: 'ai_config_${p.name}_key');
      final model = prefs.getString('ai_config_${p.name}_model') ??
          presetModels[p]!.first;
      if (key != null && key.isNotEmpty) {
        _configs[p] = AiProviderConfig(apiKey: key, model: model);
      }
    }
    notifyListeners();
  }

  Future<void> setProviderConfig(AiProvider provider,
      {String? apiKey, String? model}) async {
    final current = _configs[provider];
    final newKey = apiKey ?? current?.apiKey ?? '';
    final newModel =
        model ?? current?.model ?? presetModels[provider]!.first;

    if (newKey.isNotEmpty) {
      await _storage.write(
          key: 'ai_config_${provider.name}_key', value: newKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_config_${provider.name}_model', newModel);

    if (newKey.isNotEmpty) {
      _configs[provider] = AiProviderConfig(apiKey: newKey, model: newModel);
    } else if (current != null) {
      _configs[provider] = AiProviderConfig(apiKey: current.apiKey, model: newModel);
    }
    notifyListeners();
  }

  Future<void> clearProviderConfig(AiProvider provider) async {
    await _storage.delete(key: 'ai_config_${provider.name}_key');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_config_${provider.name}_model');
    _configs.remove(provider);
    if (_activeProvider == provider) {
      _activeProvider = configuredProviders.firstOrNull ?? AiProvider.anthropic;
      await prefs.setString(_activeProviderPrefKey, _activeProvider.name);
    }
    notifyListeners();
  }

  Future<void> setActiveProvider(AiProvider provider) async {
    _activeProvider = provider;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderPrefKey, provider.name);
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    notifyListeners();
  }

  Future<void> send(String userMessage, {String? context}) async {
    final config = _configs[_activeProvider];
    if (config == null || config.apiKey.isEmpty) return;

    _messages.add(context != null
        ? ChatMessage.user('Context:\n```\n$context\n```\n\n$userMessage')
        : ChatMessage.user(userMessage));
    _loading = true;
    notifyListeners();

    _messages.add(ChatMessage.assistant('', isStreaming: true));
    notifyListeners();

    try {
      switch (_activeProvider) {
        case AiProvider.anthropic:
          await _sendAnthropic(config);
        case AiProvider.openai:
          await _sendOpenAI(config);
        case AiProvider.gemini:
          await _sendGemini(config);
      }
    } catch (e) {
      _messages.removeLast();
      _messages.add(ChatMessage.assistant('Error: $e'));
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> _sendAnthropic(AiProviderConfig config) async {
    final apiMessages = [
      ChatMessage.system(_systemPrompt).toApiMap(),
      ..._messages
          .where((m) => !m.isStreaming && m.role != 'system')
          .take(_messages.length - 1)
          .map((m) => m.toApiMap()),
    ];

    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': config.apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': config.model,
        'max_tokens': 1024,
        'messages': apiMessages,
      }),
    );

    _messages.removeLast();
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _messages
          .add(ChatMessage.assistant((data['content'] as List).first['text'] as String));
    } else {
      _messages.add(ChatMessage.assistant(
          'Error: ${response.statusCode} — ${response.body}'));
    }
  }

  Future<void> _sendOpenAI(AiProviderConfig config) async {
    final apiMessages = [
      {'role': 'system', 'content': _systemPrompt},
      ..._messages
          .where((m) => !m.isStreaming && m.role != 'system')
          .take(_messages.length - 1)
          .map((m) => m.toApiMap()),
    ];

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'model': config.model,
        'max_tokens': 1024,
        'messages': apiMessages,
      }),
    );

    _messages.removeLast();
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _messages.add(ChatMessage.assistant(
          data['choices'][0]['message']['content'] as String));
    } else {
      _messages.add(ChatMessage.assistant(
          'Error: ${response.statusCode} — ${response.body}'));
    }
  }

  Future<void> _sendGemini(AiProviderConfig config) async {
    final contents = _messages
        .where((m) => !m.isStreaming && m.role != 'system')
        .take(_messages.length - 1)
        .map((m) => {
              'role': m.role == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m.content}
              ],
            })
        .toList();

    final response = await http.post(
      Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent?key=${config.apiKey}'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt}
          ],
        },
        'contents': contents,
      }),
    );

    _messages.removeLast();
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _messages.add(ChatMessage.assistant(
          data['candidates'][0]['content']['parts'][0]['text'] as String));
    } else {
      _messages.add(ChatMessage.assistant(
          'Error: ${response.statusCode} — ${response.body}'));
    }
  }
}
```

- [ ] **Step 2: Run tests — verify they pass**

```bash
cd app && flutter test test/providers/ai_chat_provider_test.dart
```

Expected: All 8 tests pass.

- [ ] **Step 3: Run full analyze**

```bash
cd app && flutter analyze
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add app/lib/providers/ai_chat_provider.dart app/test/providers/ai_chat_provider_test.dart
git commit -m "feat: rewrite AiChatProvider for multi-provider support (Anthropic, OpenAI, Gemini)"
```

---

### Task 4: Add AI Providers section to Settings screen

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

- [ ] **Step 1: Add imports at top of `settings_screen.dart`**

After the existing imports, add:

```dart
import '../models/ai_provider_config.dart';
import '../providers/ai_chat_provider.dart';
```

- [ ] **Step 2: Add `_AiProvidersSection()` call in `build()` before the Keyboard section**

In `_SettingsScreenState.build()`, find the line:
```dart
_Section(title: 'Keyboard', children: [
```

Insert before it:
```dart
const SizedBox(height: 24),
const _AiProvidersSection(),
```

- [ ] **Step 3: Add `_AiProvidersSection` widget class at the bottom of the file (before `_Section`)**

Append this class before the `class _Section` definition:

```dart
class _AiProvidersSection extends StatefulWidget {
  const _AiProvidersSection();

  @override
  State<_AiProvidersSection> createState() => _AiProvidersSectionState();
}

class _AiProvidersSectionState extends State<_AiProvidersSection> {
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

  void _saveKey(AiProvider p) {
    final key = _controllers[p]!.text.trim();
    if (key.isEmpty) return;
    context.read<AiChatProvider>().setProviderConfig(p, apiKey: key);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI PROVIDERS',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...AiProvider.values.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildCard(context, ai, p),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, AiChatProvider ai, AiProvider p) {
    final config = ai.configs[p];
    final models = AiChatProvider.presetModels[p]!;
    final selectedModel = config?.model ?? models.first;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _label(p),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (config != null)
                const Icon(Icons.check_circle, size: 14, color: Colors.green),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controllers[p],
            focusNode: _focusNodes[p],
            obscureText: !_showKey[p]!,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: _hint(p),
              hintStyle: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12),
              filled: true,
              fillColor: AppColors.bg,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.accent),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _showKey[p]! ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _showKey[p] = !_showKey[p]!),
                  ),
                  if (config != null)
                    IconButton(
                      icon: const Icon(Icons.clear,
                          size: 16, color: AppColors.textTertiary),
                      onPressed: () {
                        _controllers[p]!.clear();
                        context.read<AiChatProvider>().clearProviderConfig(p);
                      },
                    ),
                ],
              ),
            ),
            onSubmitted: (_) => _saveKey(p),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Model',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: selectedModel,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12),
                dropdownColor: AppColors.card,
                underline: const SizedBox(),
                isDense: true,
                items: models
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    context
                        .read<AiChatProvider>()
                        .setProviderConfig(p, model: v);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run analyze**

```bash
cd app && flutter analyze lib/widgets/settings_screen.dart
```

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat: add AI Providers section to Settings screen"
```

---

### Task 5: Update `AiChatSidebar` — provider picker + unconfigured banner

**Files:**
- Modify: `app/lib/widgets/ai_chat_sidebar.dart`

- [ ] **Step 1: Add import for `AiProvider`**

After the existing imports add:

```dart
import '../models/ai_provider_config.dart';
```

- [ ] **Step 2: Replace `_buildHeader` method**

Find and replace the entire `_buildHeader` method:

```dart
Widget _buildHeader(BuildContext context, AiChatProvider provider) {
  final configured = provider.configuredProviders;
  return Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        const Icon(Icons.smart_toy_outlined,
            size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        const Text('AI Assistant',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600)),
        if (configured.isNotEmpty) ...[
          const SizedBox(width: 8),
          DropdownButton<AiProvider>(
            value: configured.contains(provider.activeProvider)
                ? provider.activeProvider
                : configured.first,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11),
            dropdownColor: AppColors.card,
            underline: const SizedBox(),
            isDense: true,
            items: configured
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        _providerLabel(p),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                    ))
                .toList(),
            onChanged: (p) {
              if (p != null) {
                context.read<AiChatProvider>().setActiveProvider(p);
              }
            },
          ),
        ],
        const Spacer(),
        if (provider.messages.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_all,
                size: 16, color: AppColors.textSecondary),
            onPressed: provider.clear,
            tooltip: 'Clear chat',
          ),
        IconButton(
          icon: const Icon(Icons.close,
              size: 16, color: AppColors.textSecondary),
          onPressed: widget.onClose,
        ),
      ],
    ),
  );
}

String _providerLabel(AiProvider p) => switch (p) {
      AiProvider.anthropic => 'Anthropic',
      AiProvider.openai => 'OpenAI',
      AiProvider.gemini => 'Gemini',
    };
```

- [ ] **Step 3: Replace `_buildApiKeyPrompt` with `_buildUnconfiguredBanner`**

Remove the entire `_buildApiKeyPrompt` method and add:

```dart
Widget _buildUnconfiguredBanner() {
  return Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text(
      'Configure API keys in Settings → AI Providers to enable AI assistance.',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      textAlign: TextAlign.center,
    ),
  );
}
```

- [ ] **Step 4: Update the `build()` method to use the new banner**

Find:
```dart
if (!provider.configured) _buildApiKeyPrompt(context, provider),
```

Replace with:
```dart
if (!provider.configured) _buildUnconfiguredBanner(),
```

- [ ] **Step 5: Run analyze**

```bash
cd app && flutter analyze lib/widgets/ai_chat_sidebar.dart
```

Expected: no issues.

- [ ] **Step 6: Run all tests**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/ai_chat_sidebar.dart
git commit -m "feat: add provider picker to AI chat sidebar, replace inline key prompt with settings banner"
```
