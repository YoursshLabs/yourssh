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

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(500, 2400));
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

  Host target({bool recordingRedaction = true}) => Host(
        id: 'target-id',
        label: 'target',
        host: '1.2.3.4',
        username: 'root',
        recordingRedaction: recordingRedaction,
      );

  testWidgets('toggle off saves recordingRedaction=false', (tester) async {
    await pumpPanel(tester, existing: target());

    final toggle = find.text('Redact secrets in recordings');
    expect(toggle, findsOneWidget);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.recordingRedaction, isFalse);
  });

  testWidgets('existing false loads into the toggle and survives save',
      (tester) async {
    await pumpPanel(tester, existing: target(recordingRedaction: false));

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved!.recordingRedaction, isFalse);
  });
}
