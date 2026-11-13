import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_sftp_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

// ---------------------------------------------------------------------------
// Fake entry builders — use SftpFileAttrs / SftpFileMode named constructors.
// ---------------------------------------------------------------------------

// Raw mode flags (not exported from dartssh2's private _ModeFlags):
// 0x4000 = S_IFDIR, 0x8000 = S_IFREG, 0x1ED = 0755, 0x1A4 = 0644
SftpName _dir(String name) => SftpName(
      filename: name,
      longname: name,
      attr: SftpFileAttrs(
        mode: SftpFileMode.value(0x4000 | 0x1ed), // S_IFDIR | 0755
      ),
    );

SftpName _file(String name, int size) => SftpName(
      filename: name,
      longname: name,
      attr: SftpFileAttrs(
        size: size,
        mode: SftpFileMode.value(0x8000 | 0x1a4), // S_IFREG | 0644
      ),
    );

// ---------------------------------------------------------------------------
// Test host + pump helper
// ---------------------------------------------------------------------------

final _host = Host(
  id: 'h1',
  label: 'web-01',
  host: '10.0.0.1',
  port: 22,
  username: 'deploy',
);

Future<void> _pump(
  WidgetTester tester, {
  required List<SftpName> entries,
}) async {
  final storage = StorageService();
  final ssh = SshService(storage);
  final transfer = SftpTransferService(ssh);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildMobileTheme(),
      builder: ysRootBuilderTouch,
      home: MultiProvider(
        providers: [
          Provider<SshService>.value(value: ssh),
          Provider<SftpTransferService>.value(value: transfer),
        ],
        // Inject a synchronous lister so no real SSH is needed.
        child: MobileSftpScreen(
          host: _host,
          lister: (_) async => entries,
        ),
      ),
    ),
  );
  // Trigger post-frame callback + async lister.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('header shows "Files" label and host name', (tester) async {
    await _pump(tester, entries: []);
    expect(find.text('Files'), findsAtLeastNWidgets(1));
    expect(find.text('web-01'), findsAtLeastNWidgets(1));
  });

  testWidgets('breadcrumb shows home icon at root', (tester) async {
    await _pump(tester, entries: []);
    expect(find.byIcon(Icons.home_outlined), findsAtLeastNWidgets(1));
  });

  testWidgets('renders folder and file names in listing', (tester) async {
    await _pump(tester, entries: [
      _dir('var'),
      _dir('.hidden_dir'),
      _file('README.md', 1024),
      _file('.env', 512),
    ]);
    expect(find.text('var'), findsOneWidget);
    expect(find.text('.hidden_dir'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('.env'), findsOneWidget);
  });

  testWidgets('renders file size in KB', (tester) async {
    await _pump(tester, entries: [_file('data.bin', 2048)]);
    expect(find.textContaining('KB'), findsAtLeastNWidgets(1));
  });

  testWidgets('folder row shows chevron (navigable indicator)', (tester) async {
    await _pump(tester, entries: [_dir('etc')]);
    expect(find.byIcon(Icons.chevron_right), findsAtLeastNWidgets(1));
  });

  testWidgets('sort control row shows "Name" label', (tester) async {
    await _pump(tester, entries: []);
    expect(find.text('Name'), findsAtLeastNWidgets(1));
  });

  testWidgets('item count row shows correct count', (tester) async {
    await _pump(tester, entries: [_dir('a'), _file('b.txt', 100)]);
    expect(find.textContaining('2 items'), findsAtLeastNWidgets(1));
  });

  testWidgets('sensitive file (.env) shows Icons.lock_outline', (tester) async {
    await _pump(tester, entries: [_file('.env', 512)]);
    expect(find.byIcon(Icons.lock_outline), findsAtLeastNWidgets(1));
  });

  // ── forui migration (Task 15b) ───────────────────────────────────────────

  testWidgets('uses FHeader; upload action >=44px', (tester) async {
    await _pump(tester, entries: []);
    expect(find.bySubtype<FHeader>(), findsOneWidget);
    for (final a in find.byType(FHeaderAction).evaluate()) {
      final size = tester.getSize(find.byWidget(a.widget));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(find.byType(FHeaderAction), findsWidgets);
  });

  testWidgets('row, download and sort tappables are >=44px', (tester) async {
    await _pump(tester, entries: [_dir('etc'), _file('a.txt', 10)]);
    expect(tester.getSize(find.byKey(const ValueKey('sftp-sort'))).height,
        greaterThanOrEqualTo(44));
    final dl = find.byKey(const ValueKey('sftp-download'));
    expect(dl, findsOneWidget);
    final s = tester.getSize(dl);
    expect(s.width, greaterThanOrEqualTo(44));
    expect(s.height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const ValueKey('sftp-row-etc'))).height,
        greaterThanOrEqualTo(44));
  });

  testWidgets('360x640 with 60-char names and nested path: no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final longDir = 'd' * 60;
    await _pump(tester, entries: [
      _dir(longDir),
      _file('f' * 60 + '.txt', 123456789),
    ]);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(ValueKey('sftp-row-$longDir')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
