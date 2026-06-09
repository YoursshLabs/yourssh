import 'dart:convert';

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

  // 'bastion' is the only other host the panel can offer as a jump candidate.
  final bastion = Host(
    id: 'bastion-id',
    label: 'bastion',
    host: '10.0.0.1',
    username: 'jump',
  );

  // Seed the prefs blob HostProvider loads on construction so `allHosts`
  // contains bastion deterministically (avoids racing the async _load()).
  void seedHosts(List<Host> hosts) {
    SharedPreferences.setMockInitialValues({
      'yourssh.hosts': jsonEncode(hosts.map((h) => h.toJson()).toList()),
    });
  }

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
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

  // The host being edited — valid host/username/port so the form validates
  // and onSave fires.
  Host targetHost({List<String> jumpHostIds = const []}) => Host(
        id: 'target-id',
        label: 'target',
        host: '1.2.3.4',
        username: 'root',
        jumpHostIds: jumpHostIds,
      );

  testWidgets('selecting a jump host saves it onto jumpHostIds',
      (tester) async {
    seedHosts([bastion]);
    await pumpPanel(tester, existing: targetHost());

    final add = find.text('Add a Host');
    expect(add, findsOneWidget);
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();

    // Pick 'bastion' from the picker dialog.
    await tester.tap(find.text('bastion').last);
    await tester.pumpAndSettle();

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.jumpHostIds, ['bastion-id']);
  });

  testWidgets('chain renders for an existing jumpHostIds', (tester) async {
    seedHosts([bastion]);
    await pumpPanel(tester,
        existing: targetHost(jumpHostIds: ['bastion-id']));

    // Chain shows bastion + a Clear button; Add stays visible (append more).
    expect(find.text('bastion'), findsWidgets);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Add a Host'), findsOneWidget);
  });
}
