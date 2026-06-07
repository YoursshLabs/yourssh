import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester,
      {Host? existing, List<Host> allHosts = const []}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hostProvider = HostProvider(StorageService());
    for (final h in allHosts) {
      await hostProvider.addHost(h);
    }
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>.value(value: hostProvider),
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

  Host rdpHost({List<String> jumpHostIds = const []}) => Host(
        id: 'rdp-1',
        label: 'win',
        host: '10.0.0.9',
        port: 3389,
        username: 'admin',
        authType: AuthType.password,
        protocol: HostProtocol.rdp,
        domain: 'CORP',
        rdpSecurity: RdpSecurityMode.nla,
        jumpHostIds: jumpHostIds,
      );

  Host sshHost(String id) => Host(
      id: id, label: id, host: '$id.example.com', port: 22, username: 'u');

  testWidgets('selecting RDP hides SSH-only sections and flips port',
      (tester) async {
    await pumpPanel(tester);
    expect(find.text('AUTH METHOD'), findsOneWidget);

    await tester.tap(find.text('RDP'));
    await tester.pumpAndSettle();

    expect(find.text('AUTH METHOD'), findsNothing);
    expect(find.text('SFTP MODE'), findsNothing);
    expect(find.text('SESSION TEMPLATE'), findsNothing);
    expect(find.text('TEST CONNECTION'), findsNothing);
    expect(find.text('RDP SECURITY'), findsOneWidget);
    expect(find.text('3389'), findsOneWidget); // port auto-flipped from 22
  });

  testWidgets('custom port survives the protocol flip', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(
        find.widgetWithText(TextFormField, '22').first, '2222');
    await tester.tap(find.text('RDP'));
    await tester.pumpAndSettle();
    expect(find.text('2222'), findsOneWidget); // not stomped to 3389
  });

  testWidgets('saving an RDP host preserves protocol/domain/rdpSecurity',
      (tester) async {
    await pumpPanel(tester, existing: rdpHost());
    await save(tester);

    expect(saved, isNotNull);
    expect(saved!.protocol, HostProtocol.rdp);
    expect(saved!.domain, 'CORP');
    expect(saved!.rdpSecurity, RdpSecurityMode.nla);
    expect(saved!.port, 3389);
    expect(saved!.authType, AuthType.password);
  });

  testWidgets('editing an RDP host keeps createdAt', (tester) async {
    final existing = rdpHost();
    await pumpPanel(tester, existing: existing);
    await save(tester);
    expect(saved!.createdAt, existing.createdAt);
  });

  testWidgets('new host: RDP round-trips through save', (tester) async {
    await pumpPanel(tester);
    await tester.tap(find.text('RDP'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'IP or Hostname'), '10.1.1.1');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'), 'admin');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Domain (optional)'), 'CORP');
    await save(tester);

    expect(saved!.protocol, HostProtocol.rdp);
    expect(saved!.host, '10.1.1.1');
    expect(saved!.domain, 'CORP');
    expect(saved!.port, 3389);
    expect(saved!.sftpMode, SftpMode.normal);
  });

  testWidgets('deleted jump host renders as Direct connection, no crash',
      (tester) async {
    // The saved tunnel id no longer exists, but other SSH hosts do — the
    // dropdown must fall back to null instead of asserting.
    await pumpPanel(
      tester,
      existing: rdpHost(jumpHostIds: ['gone-bastion']),
      allHosts: [sshHost('other-ssh')],
    );
    expect(find.text('Direct connection'), findsOneWidget);
  });

  testWidgets('SSH tunnel section hidden when no SSH hosts exist',
      (tester) async {
    await pumpPanel(tester, existing: rdpHost());
    expect(find.text('SSH TUNNEL'), findsNothing);
  });

  testWidgets('editing an SSH host is unaffected (no RDP fields saved)',
      (tester) async {
    final ssh = sshHost('plain');
    await pumpPanel(tester, existing: ssh);
    await save(tester);
    expect(saved!.protocol, HostProtocol.ssh);
    expect(saved!.domain, isNull);
  });
}
