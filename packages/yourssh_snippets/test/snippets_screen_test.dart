import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_snippets/src/providers/snippet_provider.dart';
import 'package:yourssh_snippets/src/screens/snippets_screen.dart';

class _FakePluginContext implements YourSSHPluginContext {
  _FakePluginContext({required this.activeSessions});

  @override
  final List<SSHSessionProxy> activeSessions;

  String? sentSessionId;
  String? sentText;

  @override
  SSHSessionProxy? get activeSession {
    for (final session in activeSessions) {
      if (session.isActive) return session;
    }
    return null;
  }

  @override
  Future<String> execCommand(String sessionId, String command) async => '';

  @override
  Future<String?> getPreference(String key) async => null;

  @override
  Future<void> savePreference(String key, String value) async {}

  @override
  Future<void> sendInput(String sessionId, String text) async {
    sentSessionId = sessionId;
    sentText = text;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('run sends snippet command to active terminal session', (
    tester,
  ) async {
    final pluginContext = _FakePluginContext(
      activeSessions: const [
        SSHSessionProxy(
          sessionId: 'session-1',
          hostLabel: 'root@example',
          isConnected: true,
          isActive: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SnippetProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SnippetsScreen(pluginContext: pluginContext),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Disk usage')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Run in terminal'));
    await tester.pumpAndSettle();

    expect(pluginContext.sentSessionId, 'session-1');
    expect(pluginContext.sentText, 'df -h\n');
  });
}
