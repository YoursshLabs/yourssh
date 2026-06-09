import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
          Provider<SshService>(create: (_) => SshService(StorageService())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HostDetailPanel(
              existing: existing,
              agentProbe: () async => const AgentProbeSystem(1),
              onClose: () {},
              onSave: (host, _) async => saved = host,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final btn = find.text('SAVE ONLY');
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  Host existingHost() => Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'root',
        workingDir: '/srv/app',
        envVars: {'FOO': 'bar'},
        startupSnippet: 'htop',
        terminalThemeId: 'Dracula',
        termType: 'vt100',
        tmuxOverride: true,
      );

  testWidgets('populates template fields from the existing host',
      (tester) async {
    await pumpPanel(tester, existing: existingHost());
    expect(find.text('/srv/app'), findsOneWidget);
    expect(find.text('FOO'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
    expect(find.text('htop'), findsOneWidget);
  });

  testWidgets('round-trips template fields through save', (tester) async {
    await pumpPanel(tester, existing: existingHost());
    await save(tester);
    expect(saved, isNotNull);
    expect(saved!.workingDir, '/srv/app');
    expect(saved!.envVars, {'FOO': 'bar'});
    expect(saved!.startupSnippet, 'htop');
    expect(saved!.terminalThemeId, 'Dracula');
    expect(saved!.termType, 'vt100');
    expect(saved!.tmuxOverride, isTrue);
  });

  testWidgets('empty template fields save as null/empty', (tester) async {
    await pumpPanel(tester,
        existing: Host(label: 'srv', host: '1.2.3.4', username: 'root'));
    await save(tester);
    expect(saved, isNotNull);
    expect(saved!.workingDir, isNull);
    expect(saved!.envVars, isEmpty);
    expect(saved!.startupSnippet, isNull);
    expect(saved!.hasTemplateSetup, isFalse);
  });

  testWidgets('invalid env var name blocks save', (tester) async {
    await pumpPanel(tester, existing: existingHost());
    await tester.enterText(
        find.widgetWithText(TextFormField, 'FOO'), 'BAD-NAME');
    await save(tester);
    expect(saved, isNull, reason: 'form validation must block the save');
  });

  testWidgets('env rows can be added via the add button', (tester) async {
    await pumpPanel(tester,
        existing: Host(label: 'srv', host: '1.2.3.4', username: 'root'));
    final add = find.text('Add env variable');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'NAME'), 'PATH_X');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'value'), '/opt/x');
    await save(tester);
    expect(saved, isNotNull);
    expect(saved!.envVars, {'PATH_X': '/opt/x'});
  });
}
