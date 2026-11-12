import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ai_provider_config.dart';
import 'package:yourssh/providers/ai_chat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> secureStore = {};
  var failWrites = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    failWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'write':
          if (failWrites) throw PlatformException(code: '-34018');
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
      expect(provider.configuredProviders, isNot(contains(AiProvider.openai)));
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

  group('AiChatProvider hardening', () {
    test('keychain write failure is surfaced via lastError, not thrown',
        () async {
      failWrites = true;
      final provider = AiChatProvider();
      addTearDown(provider.dispose);
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.openai, apiKey: 'sk-x');
      expect(provider.lastError, isNotNull);
      provider.clearError();
      expect(provider.lastError, isNull);
    });

    test('keychain read failure during load does not throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: '-34018');
      });
      final provider = AiChatProvider();
      addTearDown(provider.dispose);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(provider.lastError, isNotNull);
    });

    test('macOS storage pins the legacy keychain', () {
      expect(
          AiChatProvider.macOsKeychainOptions
              .toMap()['useDataProtectionKeyChain'],
          'false');
    });

    test('Gemini key goes in x-goog-api-key header, not the URL', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'hi'}
                    ]
                  }
                }
              ]
            }),
            200);
      });
      final provider = AiChatProvider(client: client);
      addTearDown(provider.dispose);
      await Future.delayed(Duration.zero);
      await provider.setProviderConfig(AiProvider.gemini, apiKey: 'AIza-secret');
      await provider.setActiveProvider(AiProvider.gemini);
      await provider.send('hello');
      expect(captured.url.toString(), isNot(contains('AIza-secret')));
      expect(captured.url.query, isEmpty);
      expect(captured.headers['x-goog-api-key'], 'AIza-secret');
    });
  });
}
