import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/deploy_key_dialog.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakeSsh extends SshService {
  _FakeSsh() : super(StorageService());
  final calls = <String>[];
  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async {
    calls.add(host.id);
    return (stdout: 'ADDED', stderr: '', exitCode: 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final longLabel = 'h' * 60;

  late _FakeSsh ssh;

  Future<void> pump(WidgetTester tester) async {
    ssh = _FakeSsh();
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hosts = HostProvider(StorageService());
    await hosts.ready;
    await hosts.addHost(
      Host(id: 'a', label: 'prod-db', host: '10.0.0.1', username: 'root'),
    );
    await hosts.addHost(
      Host(id: 'b', label: longLabel, host: '10.0.0.2', username: 'root'),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          Provider<SshService>.value(value: ssh),
        ],
        child: ysTestApp(
          Builder(
            builder: (ctx) => FButton(
              onPress: () => showYsDialog(
                ctx,
                builder: (_) => DeployKeyDialog(
                  entry: SshKeyEntry(
                    label: 'id_ed25519',
                    algorithm: KeyAlgorithm.ed25519,
                    publicKey: 'ssh-ed25519 AAAA test',
                    privateKeyPath: '/tmp/k',
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows title, search field, hosts and Close', (tester) async {
    await pump(tester);
    expect(find.text('Deploy "id_ed25519" to host'), findsOneWidget);
    expect(find.byType(FTextField), findsOneWidget);
    expect(find.text('prod-db'), findsOneWidget);
    expect(find.text('root@10.0.0.1'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.byType(FTile), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search field has focus; typing filters hosts', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(EditableText), '10.0.0.1');
    await tester.pump();
    expect(find.text('prod-db'), findsOneWidget);
    expect(find.text('root@10.0.0.2'), findsNothing);
    await tester.enterText(find.byType(EditableText), 'zzz');
    await tester.pump();
    expect(find.text('No hosts'), findsOneWidget);
  });

  testWidgets('60-char label at 900x600 does not overflow', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(longLabel), findsOneWidget);
  });

  testWidgets('tapping a host deploys, closes and toasts', (tester) async {
    await pump(tester);
    await tester.tap(find.text('prod-db'));
    await tester.pumpAndSettle();
    expect(ssh.calls, ['a']);
    expect(find.byType(DeployKeyDialog), findsNothing);
    expect(find.text('Public key added to prod-db'), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(DeployKeyDialog), findsNothing);
  });
}
