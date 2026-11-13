import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_sftp_screen.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart';

class _FakeSftp implements SftpClient {
  _FakeSftp(this.names, {this.fail = false});
  final List<String> names;
  final bool fail;
  bool closed = false;

  @override
  Future<List<SftpName>> listdir(String path) async {
    if (fail) throw StateError('channel closed');
    return [
      for (final n in names)
        SftpName(
            filename: n, longname: n, attr: SftpFileAttrs(size: 1, mode: null)),
    ];
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// Updated after Task 13 redesign: MobileSftpScreen is now contextual and
// requires a [Host]. The full smoke-test suite lives in
// test/mobile/screens/sftp_screen_test.dart.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows empty folder message with empty listing', (tester) async {
    final storage = StorageService();
    final ssh = SshService(storage);
    final transfer = SftpTransferService(ssh);
    final host = Host(
      id: 'h1',
      label: 'web-01',
      host: '10.0.0.1',
      port: 22,
      username: 'deploy',
    );

    await tester.pumpWidget(MaterialApp(
      builder: ysRootBuilderTouch,
      home: MultiProvider(
        providers: [
          Provider<SshService>.value(value: ssh),
          Provider<SftpTransferService>.value(value: transfer),
        ],
        child: MobileSftpScreen(
          host: host,
          lister: (_) async => [],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Empty'), findsOneWidget);
  });

  testWidgets('recovers when the cached SFTP channel died while paused',
      (tester) async {
    final storage = StorageService();
    final ssh = SshService(storage);
    final transfer = SftpTransferService(ssh);
    final host = Host(
        id: 'h1', label: 'web-01', host: '10.0.0.1', port: 22, username: 'u');
    final dead = _FakeSftp(['old'], fail: true);
    final fresh = _FakeSftp(['new.txt']);
    final queue = [dead, fresh];
    var opened = 0;

    await tester.pumpWidget(MaterialApp(
      builder: ysRootBuilderTouch,
      home: MultiProvider(
        providers: [
          Provider<SshService>.value(value: ssh),
          Provider<SftpTransferService>.value(value: transfer),
        ],
        child: MobileSftpScreen(
          host: host,
          sftpOpener: () async {
            opened++;
            return queue.removeAt(0);
          },
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('new.txt'), findsOneWidget);
    expect(opened, 2, reason: 'the dead channel was replaced');
    expect(dead.closed, isTrue);
  });
}
