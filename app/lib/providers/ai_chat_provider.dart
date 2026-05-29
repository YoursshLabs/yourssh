import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class AiChatProvider extends ChangeNotifier {
  static const _systemPrompt =
      'You are an SSH command assistant embedded in an SSH client app. '
      'Help the user with shell commands, explain error messages, suggest fixes, and assist with DevOps tasks. '
      'Keep responses concise and practical. Use code blocks for commands.';

  static const _keyStorageKey = 'ai_api_key';

  final _storage = const FlutterSecureStorage();
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  String? _apiKey;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  bool get configured => _apiKey != null && _apiKey!.isNotEmpty;

  AiChatProvider() {
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    _apiKey = await _storage.read(key: _keyStorageKey);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    await _storage.write(key: _keyStorageKey, value: key);
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    _apiKey = null;
    await _storage.delete(key: _keyStorageKey);
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    notifyListeners();
  }

  Future<void> send(String userMessage, {String? context}) async {
    if (_apiKey == null || _apiKey!.isEmpty) return;

    final userMsg = context != null
        ? ChatMessage.user('Context:\n```\n$context\n```\n\n$userMessage')
        : ChatMessage.user(userMessage);

    _messages.add(userMsg);
    _loading = true;
    notifyListeners();

    final placeholder = ChatMessage.assistant('', isStreaming: true);
    _messages.add(placeholder);
    notifyListeners();

    try {
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
          'x-api-key': _apiKey!,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5-20251001',
          'max_tokens': 1024,
          'messages': apiMessages,
        }),
      );

      _messages.removeLast();
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = (data['content'] as List).first['text'] as String;
        _messages.add(ChatMessage.assistant(content));
      } else {
        _messages.add(ChatMessage.assistant(
            'Error: ${response.statusCode} — ${response.body}'));
      }
    } catch (e) {
      _messages.removeLast();
      _messages.add(ChatMessage.assistant('Error: $e'));
    }

    _loading = false;
    notifyListeners();
  }
}
