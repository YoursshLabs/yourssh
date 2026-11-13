import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/terminal_header_chips.dart';

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
  });

  testWidgets('chips follow edits of the stored host and ignore output',
      (tester) async {
    final host = Host(
      id: 'h1',
      label: 'prod',
      host: 'prod.example.com',
      username: 'deploy',
      tags: const ['a', 'b'],
    );
    final session = SshSession(host: host);
    final hosts = HostProvider(StorageService());
    final shell = ShellIntegrationProvider();
    await tester.runAsync(() async {
      await hosts.ready;
      await hosts.addHost(host);
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hosts),
        ChangeNotifierProvider<ShellIntegrationProvider>.value(value: shell),
      ],
      child: ysTestApp(TerminalHeaderChips(session: session)),
    ));
    expect(find.text('prod'), findsOneWidget);
    expect(find.text('deploy@prod.example.com'), findsOneWidget);

    await tester.runAsync(() => hosts.updateHost(
          host.copyWith(label: 'renamed', username: 'ops')
            ..tags = const ['x', 'y'],
        ));
    await tester.pump();
    expect(find.text('renamed'), findsOneWidget);
    expect(find.text('ops@prod.example.com'), findsOneWidget);
    expect(find.text('x'), findsOneWidget);

    // An edit of some other host does not rebuild the chips.
    final other = Host(id: 'h2', label: 'o', host: 'o', username: 'u');
    await tester.runAsync(() => hosts.addHost(other));
    await tester.pump();
    final builds = TerminalHeaderChips.debugBuildCount;
    session.terminal.write('output\r\n');
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
        () => hosts.updateHost(other.copyWith(label: 'o2')));
    await tester.pump();
    expect(TerminalHeaderChips.debugBuildCount, builds);
  });
}
