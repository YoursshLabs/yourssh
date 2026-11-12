// Regression: the SFTP panel holds the Host snapshot captured when its slot
// picked the source. Switching that host to Sudo mode afterwards left the
// snapshot on SftpMode.normal, so the header showed no "root" badge — the
// visible half of the bug where listings silently ran unelevated and the
// server answered "Permission denied (code 3)".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/sftp_panel_provider.dart';
import 'package:yourssh/services/external_edit_service.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/sftp_panel.dart';

class _FakeTransferService extends SftpTransferService {
  _FakeTransferService() : super(SshService(StorageService()));

  @override
  Future<List<SftpEntry>> listDirectory(Host host, String path) async => [];
}

/// Serves the live host list without touching storage.
class _FakeHostProvider extends HostProvider {
  _FakeHostProvider(this._hosts) : super(StorageService());

  final List<Host> _hosts;

  @override
  Host? byId(String id) => _hosts.where((h) => h.id == id).firstOrNull;

  @override
  List<Host> get allHosts => List.unmodifiable(_hosts);
}

Host _host(SftpMode mode) => Host(
      id: 'h1',
      label: 'h1',
      host: 'h1.example.com',
      username: 'user',
      sftpMode: mode,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Future<void> pumpPanel(WidgetTester tester,
      {required Host snapshot, required HostProvider hosts}) async {
    final fake = _FakeTransferService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HostProvider>.value(value: hosts),
          Provider<SftpTransferService>.value(value: fake),
          Provider<ExternalEditService>.value(value: ExternalEditService(fake)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SftpPanel(
              host: snapshot,
              panelId: 'remote_left',
              provider: SftpPanelProvider(),
              onChangeHost: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('badge follows the live host, not the stale snapshot',
      (tester) async {
    await pumpPanel(tester,
        snapshot: _host(SftpMode.normal),
        hosts: _FakeHostProvider([_host(SftpMode.sudo)]));

    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('no badge when the live host is back on default SFTP',
      (tester) async {
    await pumpPanel(tester,
        snapshot: _host(SftpMode.sudo),
        hosts: _FakeHostProvider([_host(SftpMode.normal)]));

    expect(find.text('root'), findsNothing);
  });
}
