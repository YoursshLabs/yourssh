import 'package:uuid/uuid.dart';

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime createdAt;
  final bool isStreaming;

  ChatMessage._({
    required this.role,
    required this.content,
    this.isStreaming = false,
  })  : id = const Uuid().v4(),
        createdAt = DateTime.now();

  factory ChatMessage.user(String content) =>
      ChatMessage._(role: 'user', content: content);

  factory ChatMessage.assistant(String content, {bool isStreaming = false}) =>
      ChatMessage._(role: 'assistant', content: content, isStreaming: isStreaming);

  factory ChatMessage.system(String content) =>
      ChatMessage._(role: 'system', content: content);

  Map<String, dynamic> toApiMap() => {'role': role, 'content': content};

  ChatMessage copyWith({String? content, bool? isStreaming}) => ChatMessage._(
        role: role,
        content: content ?? this.content,
        isStreaming: isStreaming ?? this.isStreaming,
      );
}
