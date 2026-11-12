import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ai_provider_config.dart';
import 'package:yourssh/providers/ai_chat_provider.dart';
import 'package:yourssh/widgets/ai_chat_sidebar.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

final _input = find.descendant(
  of: find.byKey(const ValueKey('ai-chat-input')),
  matching: find.byType(EditableText),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> secureStore = {};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'write':
              secureStore[key!] = call.arguments['value'] as String;
              return null;
            case 'read':
              return secureStore[key];
            case 'delete':
              secureStore.remove(key);
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final reply = MockClient(
    (_) async => http.Response(
      jsonEncode({
        'content': [
          {'text': 'pong'},
        ],
      }),
      200,
    ),
  );

  Future<AiChatProvider> pump(
    WidgetTester tester, {
    bool configured = true,
    VoidCallback? onClose,
  }) async {
    final provider = AiChatProvider(client: reply);
    await tester.runAsync(() async {
      if (configured) {
        await provider.setProviderConfig(
          AiProvider.anthropic,
          apiKey: 'sk-test',
        );
      }
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: ysTestApp(AiChatSidebar(onClose: onClose ?? () {})),
      ),
    );
    await tester.pump();
    return provider;
  }

  testWidgets('unconfigured: banner shown, Send disabled', (tester) async {
    await pump(tester, configured: false);
    expect(find.text('AI Assistant'), findsOneWidget);
    expect(find.textContaining('Configure API keys in Settings'), findsOneWidget);
    expect(find.textContaining('Ask anything about SSH commands'), findsOneWidget);
    final send = tester.widget<FButton>(
      find.descendant(
        of: find.byTooltip('Send'),
        matching: find.byType(FButton),
      ),
    );
    expect(send.onPress, isNull);
  });

  testWidgets('configured: provider select shows the active provider', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('ai-chat-provider')), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
  });

  testWidgets('Close button calls onClose', (tester) async {
    var closed = false;
    await pump(tester, onClose: () => closed = true);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(closed, isTrue);
  });

  testWidgets('Send button sends the typed text and clears the input', (
    tester,
  ) async {
    final provider = await pump(tester);
    await tester.enterText(_input, 'ls -la');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(provider.messages.first.role, 'user');
    expect(provider.messages.first.content, 'ls -la');
    expect(tester.widget<EditableText>(_input).controller.text, '');
    expect(find.byTooltip('Clear chat'), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('pong'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(provider.messages, isEmpty);
  });

  testWidgets('submit action (Enter) in the input sends', (tester) async {
    final provider = await pump(tester);
    await tester.enterText(_input, 'whoami');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(provider.messages.first.content, 'whoami');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  });

  testWidgets('empty input is not sent', (tester) async {
    final provider = await pump(tester);
    await tester.enterText(_input, '   ');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(provider.messages, isEmpty);
  });

  testWidgets('60-char content does not overflow at 900x600', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final provider = await pump(tester);
    await tester.enterText(_input, 'W' * 60);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(provider.messages.first.content, 'W' * 60);
    expect(tester.takeException(), isNull);
  });
}
