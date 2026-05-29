import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/chat_message.dart';

void main() {
  test('ChatMessage.user has correct role', () {
    final m = ChatMessage.user('ls -la');
    expect(m.role, 'user');
    expect(m.content, 'ls -la');
  });

  test('ChatMessage.assistant has correct role', () {
    final m = ChatMessage.assistant('The ls command lists files.');
    expect(m.role, 'assistant');
  });

  test('ChatMessage.toApiMap includes role and content', () {
    final m = ChatMessage.user('hello');
    final map = m.toApiMap();
    expect(map['role'], 'user');
    expect(map['content'], 'hello');
  });
}
