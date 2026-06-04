// Back/forward navigation in the remote SFTP panel's path bar (parity with
// the local panel's chevron buttons backed by the provider history stack).
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
    if (path == '/a') {
      return [
        SftpEntry(
            name: 'b',
            path: '/a/b',
            isDirectory: true,
            size: 0,
            modifiedAt: DateTime(2024)),
      ];
    }
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeTransferService> pumpPanel(
      WidgetTester tester, SftpPanelProvider provider) async {
    final fake = _FakeTransferService();
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
          Provider<ExternalEditService>.value(value: ExternalEditService(fake)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SftpPanel(
              host: host,
              panelId: 'remote_left',
              provider: provider,
              onChangeHost: () {},
              initialPath: '/a',
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame initial load
    await tester.pump(); // async listDirectory completes
    return fake;
  }

  // The breadcrumb separator also uses chevron_right, so target the
  // IconButton ancestor — the separator icon sits outside any button.
  final backButton = find.ancestor(
      of: find.byIcon(Icons.chevron_left), matching: find.byType(IconButton));
  final forwardButton = find.ancestor(
      of: find.byIcon(Icons.chevron_right), matching: find.byType(IconButton));

  testWidgets('chevrons are disabled before any navigation', (tester) async {
    final provider = SftpPanelProvider();
    await pumpPanel(tester, provider);

    final back = tester.widget<IconButton>(backButton);
    final forward = tester.widget<IconButton>(forwardButton);
    expect(back.onPressed, isNull,
        reason: 'nothing to go back to on the initial path');
    expect(forward.onPressed, isNull);
  });

  testWidgets('back returns to the previous directory and forward redoes it',
      (tester) async {
    final provider = SftpPanelProvider();
    final fake = await pumpPanel(tester, provider);

    // Navigate into /a/b by tapping the directory entry.
    await tester.tap(find.text('b'));
    await tester.pump();
    await tester.pump();
    expect(provider.currentPath, '/a/b');

    await tester.tap(backButton);
    await tester.pump();
    await tester.pump();
    expect(provider.currentPath, '/a');
    expect(fake.listedPaths.last, '/a',
        reason: 'goBack must re-list the previous directory');

    await tester.tap(forwardButton);
    await tester.pump();
    await tester.pump();
    expect(provider.currentPath, '/a/b');
    expect(fake.listedPaths.last, '/a/b');
    expect(provider.canGoForward, isFalse,
        reason: 'back+forward must not grow the history');
  });
}
