// Regression for the dual-panel path-preservation promise: switching a
// slot's source away and back must resume at the remembered path, which the
// screen passes to SftpPanel as `initialPath` (the panel is recreated on
// every source switch because its key embeds the host id).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/providers/sftp_panel_provider.dart';
import 'package:yourssh/services/external_edit_service.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/sftp_panel.dart';

class _FakeTransferService extends SftpTransferService {
  _FakeTransferService() : super(SshService(StorageService()));

  final List<String> listedPaths = [];

  @override
  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    listedPaths.add(path);
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SftpPanel loads initialPath instead of / on mount',
      (tester) async {
    final fake = _FakeTransferService();
    final provider = SftpPanelProvider();
    final host = Host(
      id: 'h1',
      label: 'h1',
      host: 'h1.example.com',
      port: 22,
      username: 'user',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SftpTransferService>.value(value: fake),
          Provider<ExternalEditService>.value(
              value: ExternalEditService(fake)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SftpPanel(
              host: host,
              panelId: 'remote_left',
              provider: provider,
              onChangeHost: () {},
              initialPath: '/var/www',
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame initial load

    expect(fake.listedPaths, ['/var/www'],
        reason: 'panel must resume at the remembered path, not /');
    expect(provider.currentPath, '/var/www');
  });
}
