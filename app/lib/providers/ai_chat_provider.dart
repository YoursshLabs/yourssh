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
    final newModel = model ?? current?.model ?? presetModels[provider]!.first;

    if (newKey.isNotEmpty) {
      await _storage.write(
          key: 'ai_config_${provider.name}_key', value: newKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_config_${provider.name}_model', newModel);

    if (newKey.isNotEmpty) {
      _configs[provider] = AiProviderConfig(apiKey: newKey, model: newModel);
    } else if (current != null) {
      _configs[provider] =
          AiProviderConfig(apiKey: current.apiKey, model: newModel);
    }
    notifyListeners();
  }

  Future<void> clearProviderConfig(AiProvider provider) async {
    await _storage.delete(key: 'ai_config_${provider.name}_key');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_config_${provider.name}_model');
    _configs.remove(provider);
    if (_activeProvider == provider) {
      _activeProvider =
          configuredProviders.firstOrNull ?? AiProvider.anthropic;
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
    // Re-entrancy guard: concurrent send()s would each manage their own
    // streaming placeholder via removeLast(), which can pop the wrong message.
    if (_loading) return;
    final config = _configs[_activeProvider];
    if (config == null || config.apiKey.isEmpty) return;

    _messages.add(context != null
        ? ChatMessage.user('Context:\n```\n$context\n```\n\n$userMessage')
        : ChatMessage.user(userMessage));
    _loading = true;
    notifyListeners();

    final placeholder = ChatMessage.assistant('', isStreaming: true);
    _messages.add(placeholder);
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
      // Remove our specific placeholder by identity, not by position — clear()
      // could have run between dispatch and error.
      _messages.remove(placeholder);
      _messages.add(ChatMessage.assistant('Error: $e'));
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Conversation history sent to the model: drops system messages and the
  /// in-flight streaming placeholder (the last entry).
  Iterable<ChatMessage> _historyForApi() => _messages
      .where((m) => !m.isStreaming && m.role != 'system')
      .take(_messages.length - 1);

  Future<void> _sendAnthropic(AiProviderConfig config) async {
    final apiMessages = [
      ChatMessage.system(_systemPrompt).toApiMap(),
      ..._historyForApi().map((m) => m.toApiMap()),
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
      _messages.add(ChatMessage.assistant(
          (data['content'] as List).first['text'] as String));
    } else {
      _messages.add(ChatMessage.assistant(
          'Error: ${response.statusCode} — ${response.body}'));
    }
  }

  Future<void> _sendOpenAI(AiProviderConfig config) async {
    final apiMessages = [
      {'role': 'system', 'content': _systemPrompt},
      ..._historyForApi().map((m) => m.toApiMap()),
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
    final contents = _historyForApi()
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
