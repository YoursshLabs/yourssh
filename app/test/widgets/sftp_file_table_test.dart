// Both SFTP panels on YsFileTable: keyboard (focus/Enter), the shared entry
// context menu opened from a table row, sorting, range selection, and the
// 900×600 window minimum with long paths, names and host labels.
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/local_entry.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/local_file_panel_provider.dart';
import 'package:yourssh/providers/sftp_panel_provider.dart';
import 'package:yourssh/services/external_edit_service.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/util/entry_sort.dart';
import 'package:yourssh/widgets/dual_panel_sftp_screen.dart';
import 'package:yourssh/widgets/file_panel_chrome.dart';
import 'package:yourssh/widgets/local_file_panel.dart';
import 'package:yourssh/widgets/sftp_panel.dart';
import 'package:yourssh/widgets/sftp_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show FCheckbox, FCircularProgress;

import '../helpers/ys_test_app.dart';

LocalEntry _local(
  String dir,
  String name, {
  bool isDir = false,
  int size = 10,
}) => LocalEntry(
  name: name,
  path: '$dir/$name',
  isDirectory: isDir,
  size: size,
  modifiedAt: DateTime(2026),
  permissions: isDir ? 'drwxr-xr-x' : '-rw-r--r--',
  mode: isDir ? 0x41ed : 0x81a4,
);

SftpEntry _remote(
  String dir,
  String name, {
  bool isDir = false,
  int size = 0,
}) => SftpEntry(
  name: name,
  path: dir == '/' ? '/$name' : '$dir/$name',
  isDirectory: isDir,
  size: size,
  modifiedAt: DateTime(2026),
  mode: isDir ? 0x41ed : 0x81a4,
);

class _FakeTransferService extends SftpTransferService {
  _FakeTransferService(this.listing, {this.latency = Duration.zero})
    : super(SshService(StorageService()));

  final Map<String, List<SftpEntry>> listing;
  final Duration latency;
  final List<String> listedPaths = [];

  @override
  Future<List<SftpEntry>> listDirectory(Host host, String path) async {
    listedPaths.add(path);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    // Fresh objects on every call, like a real listing.
    return [
      for (final e in listing[path] ?? const <SftpEntry>[])
        SftpEntry(
          name: e.name,
          path: e.path,
          isDirectory: e.isDirectory,
          size: e.size,
          modifiedAt: e.modifiedAt,
          mode: e.mode,
        ),
    ];
  }
}

/// Serves a canned listing; every other SftpClient member is unused.
class _FakeSftp implements SftpClient {
  _FakeSftp(this.listing, {this.latency = Duration.zero});

  final Map<String, List<SftpName>> listing;
  final Duration latency;
  final List<String> listed = [];

  @override
  Future<List<SftpName>> listdir(String path) async {
    listed.add(path);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return [...?listing[path]];
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSsh extends SshService {
  _FakeSsh(this.sftp) : super(StorageService());

  final SftpClient sftp;

  @override
  Future<SftpClient> openSftp(Host snapshot, {bool interactive = true}) async =>
      sftp;
}

SftpName _name(String name, {bool dir = false, int size = 0}) => SftpName(
  filename: name,
  longname: name,
  attr: SftpFileAttrs(
    size: size,
    mode: SftpFileMode.value(dir ? 0x41ed : 0x81a4),
  ),
);

Host _host({String label = 'h1', SftpMode mode = SftpMode.normal}) => Host(
  id: 'h1',
  label: label,
  host: 'h1.example.com',
  username: 'user',
  sftpMode: mode,
);

Future<LocalFilePanelProvider> _pumpLocal(
  WidgetTester tester,
  List<LocalEntry> entries, {
  String path = '/files',
}) async {
  final provider = LocalFilePanelProvider.forTest(path);
  addTearDown(provider.dispose);
  await tester.pumpWidget(ysTestApp(LocalFilePanel(provider: provider)));
  await tester.pump(); // mount reload kicks off (never lands in fake zone)
  provider.setEntriesForTest(entries);
  await tester.pump();
  return provider;
}

Future<(SftpPanelProvider, _FakeTransferService)> _pumpRemote(
  WidgetTester tester,
  Map<String, List<SftpEntry>> listing, {
  String initialPath = '/',
  Host? host,
  Duration latency = Duration.zero,
}) async {
  final fake = _FakeTransferService(listing, latency: latency);
  final provider = SftpPanelProvider();
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<SftpTransferService>.value(value: fake),
        Provider<ExternalEditService>.value(value: ExternalEditService(fake)),
      ],
      child: ysTestApp(
        SftpPanel(
          host: host ?? _host(),
          panelId: 'remote_left',
          provider: provider,
          onChangeHost: () {},
          initialPath: initialPath,
        ),
      ),
    ),
  );
  await tester.pump(); // post-frame initial load
  await tester.pump(latency); // async listDirectory completes
  await tester.pump();
  return (provider, fake);
}

/// forui buttons settle their press feedback 100 ms after a tap.
const _pressFeedback = Duration(milliseconds: 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('keyboard', () {
    testWidgets('local panel: focus a folder row, Enter opens it', (
      tester,
    ) async {
      final provider = await _pumpLocal(tester, [
        _local('/files', 'docs', isDir: true),
        _local('/files', 'a.txt'),
      ]);

      await tester.tap(find.text('docs')); // selects and focuses the table
      await tester.pump(const Duration(milliseconds: 500));
      expect(provider.currentPath, '/files', reason: 'a click only selects');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.currentPath, '/files/docs');
    });

    testWidgets('local panel: arrows + Space select without the mouse', (
      tester,
    ) async {
      final provider = await _pumpLocal(tester, [
        _local('/files', 'a.txt'),
        _local('/files', 'b.txt'),
      ]);
      await tester.tap(find.text('a.txt'));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(provider.selectedEntries.map((e) => e.name).toSet(), {
        'a.txt',
        'b.txt',
      });
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('remote panel: focus (Tab-like, no click) puts the cursor on '
        'the first row; Enter opens that folder', (tester) async {
      final (provider, fake) = await _pumpRemote(tester, {
        '/': [_remote('/', 'etc', isDir: true), _remote('/', 'x.log')],
      });

      tester
          .widget<Focus>(find.byKey(const ValueKey('ys-file-table-focus')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(provider.currentPath, '/etc');
      expect(fake.listedPaths.last, '/etc');
    });
  });

  group('selection and sorting', () {
    testWidgets('Shift-click selects the range between two rows', (
      tester,
    ) async {
      final provider = await _pumpLocal(tester, [
        _local('/files', 'a.txt'),
        _local('/files', 'b.txt'),
        _local('/files', 'c.txt'),
        _local('/files', 'd.txt'),
      ]);

      await tester.tap(find.text('b.txt'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('d.txt'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(provider.selectedEntries.map((e) => e.name).toSet(), {
        'b.txt',
        'c.txt',
        'd.txt',
      });
    });

    testWidgets('pressing the Size header sorts by size, again reverses', (
      tester,
    ) async {
      final provider = await _pumpLocal(tester, [
        _local('/files', 'docs', isDir: true, size: 4096),
        _local('/files', 'a.txt', size: 30),
        _local('/files', 'b.txt', size: 10),
        _local('/files', 'c.txt', size: 20),
      ]);

      List<String> order() =>
          provider.filteredEntries.map((e) => e.name).toList();
      double y(String name) => tester.getTopLeft(find.text(name)).dy;

      await tester.tap(find.text('Size'));
      await tester.pump(_pressFeedback);
      expect(order(), [
        'docs',
        'b.txt',
        'c.txt',
        'a.txt',
      ], reason: 'folders stay first');
      expect(y('b.txt'), lessThan(y('c.txt')));

      await tester.tap(find.text('Size'));
      await tester.pump(_pressFeedback);
      expect(order(), ['docs', 'a.txt', 'c.txt', 'b.txt']);
      expect(y('a.txt'), lessThan(y('b.txt')));
    });
  });

  group('context menu', () {
    testWidgets('right-clicking a row opens the entry menu with every item', (
      tester,
    ) async {
      await _pumpLocal(tester, [_local('/files', 'a.txt')]);

      await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      for (final item in [
        'Open',
        'Open with',
        'Copy to target directory',
        'Rename',
        'Delete',
        'Refresh',
        'New Folder',
        'Edit Permissions',
        'Copy path',
      ]) {
        expect(find.text(item), findsOneWidget, reason: 'missing $item');
      }
      // Standalone panel: no opposite panel to copy into.
      expect(find.text('No target panel'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsNothing);
    });

    testWidgets('a click outside the menu only closes it (it does not open '
        'the row underneath)', (tester) async {
      final (provider, fake) = await _pumpRemote(tester, {
        '/': [_remote('/', 'etc', isDir: true), _remote('/', 'x.log')],
      });
      final listed = fake.listedPaths.length;

      await tester.tap(find.text('x.log'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsOneWidget);

      await tester.tap(find.text('etc'));
      await tester.tap(find.text('etc')); // even a double click
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsNothing);
      expect(provider.currentPath, '/');
      expect(provider.selectedEntries, isEmpty);
      expect(fake.listedPaths.length, listed);
    });

    testWidgets('right-clicking a row checkbox opens the menu too', (
      tester,
    ) async {
      await _pumpLocal(tester, [_local('/files', 'a.txt')]);
      await tester.tap(find.byType(FCheckbox).at(1), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsOneWidget);
    });

    testWidgets('a disabled reason from the dual-panel screen is shown', (
      tester,
    ) async {
      final provider = LocalFilePanelProvider.forTest('/files');
      addTearDown(provider.dispose);
      var copied = 0;
      await tester.pumpWidget(
        ysTestApp(
          LocalFilePanel(
            provider: provider,
            onCopyToTarget: (_) => copied++,
            copyToTargetBlockReason: (_) => 'Both panels show this folder',
          ),
        ),
      );
      await tester.pump();
      provider.setEntriesForTest([_local('/files', 'a.txt')]);
      await tester.pump();

      await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Both panels show this folder'), findsOneWidget);
      await tester.tap(
        find.text('Copy to target directory'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(copied, 0);
    });
  });

  group('900×600 window', () {
    final longDir = '/home/deploy/${'p' * 47}'; // 60 characters
    final longFile = '${'f' * 56}.txt'; // 60 characters
    final longFolder = 'd' * 60;

    setUp(() {
      expect(longDir.length, 60);
      expect(longFile.length, 60);
    });

    testWidgets('both panels with a 60-char path, file name and host label '
        'do not overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final local = LocalFilePanelProvider.forTest(longDir);
      addTearDown(local.dispose);
      final remote = SftpPanelProvider();
      addTearDown(remote.dispose);
      final fake = _FakeTransferService({
        longDir: [
          _remote(longDir, longFolder, isDir: true),
          _remote(longDir, longFile, size: 123456789),
        ],
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SftpTransferService>.value(value: fake),
            Provider<ExternalEditService>.value(
              value: ExternalEditService(fake),
            ),
          ],
          child: ysTestApp(
            Row(
              children: [
                const SizedBox(width: 200), // the app sidebar
                Expanded(
                  child: LocalFilePanel(provider: local, onChangeSource: () {}),
                ),
                const SizedBox(width: 36), // the transfer bar
                Expanded(
                  child: SftpPanel(
                    host: _host(label: 'h' * 60, mode: SftpMode.sudo),
                    panelId: 'remote_right',
                    provider: remote,
                    onChangeHost: () {},
                    initialPath: longDir,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      local.setEntriesForTest([
        _local(longDir, longFolder, isDir: true),
        _local(longDir, longFile, size: 123456789),
      ]);
      await tester.pump();

      expect(find.text(longFile), findsNWidgets(2));
      expect(find.text('root'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Filter bars open as well.
      local.toggleFilterVisible();
      remote.toggleFilterVisible();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dual-panel screen fits with a 60-char host label', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<bool>(false);
      addTearDown(notifier.dispose);
      final storage = StorageService();
      final hosts = HostProvider(storage);
      await hosts.addHost(
        Host(
          label: 'h' * 60,
          host: '127.0.0.1',
          username: 'root',
          authType: AuthType.password,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SshService>(create: (_) => SshService(storage)),
            ChangeNotifierProvider.value(value: hosts),
          ],
          child: ysTestApp(
            Row(
              children: [
                const SizedBox(width: 200),
                Expanded(
                  child: DualPanelSftpScreen(connectionNotifier: notifier),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Select host'));
      await tester.pump(_pressFeedback);
      await tester.tap(find.text('h' * 60));
      await tester.pump(_pressFeedback);
      expect(tester.takeException(), isNull);
      // Both transfer buttons keep their tooltips.
      expect(find.byTooltip('Copy →'), findsOneWidget);
      expect(find.byTooltip('Copy ←'), findsOneWidget);
    });
  });

  group('dual-panel split', () {
    testWidgets('starts even; dragging the gutter resizes the panels and the '
        'transfer buttons follow it, also across a window resize', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<bool>(false);
      addTearDown(notifier.dispose);
      final storage = StorageService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SshService>(create: (_) => SshService(storage)),
            ChangeNotifierProvider(create: (_) => HostProvider(storage)),
          ],
          child: ysTestApp(DualPanelSftpScreen(connectionNotifier: notifier)),
        ),
      );
      await tester.pump();

      double buttonX() => tester.getCenter(find.byTooltip('Copy →')).dx;
      double localWidth() => tester.getSize(find.byType(LocalFilePanel)).width;
      expect(buttonX(), closeTo(600, 1));
      expect(localWidth(), closeTo(600 - 18, 1));

      // Drag the gutter above the buttons.
      await tester.dragFrom(const Offset(600, 60), const Offset(120, 0));
      // The local listing spins forever here (no real IO in the fake zone),
      // so pump frames instead of settling.
      await tester.pump(const Duration(milliseconds: 100));
      expect(buttonX(), greaterThan(680));
      expect(localWidth(), closeTo(buttonX() - 18, 2));

      await tester.binding.setSurfaceSize(const Size(1000, 600));
      await tester.pump(const Duration(milliseconds: 100));
      // forui rescales the regions (not exactly proportionally when it
      // shrinks them, and never below the 35 % minimum); the buttons must
      // sit on the gutter wherever it ended up.
      expect(buttonX(), greaterThan(500), reason: 'the split stays dragged');
      expect(
        localWidth(),
        closeTo(buttonX() - 18, 2),
        reason: 'the buttons stay on the gutter after a window resize',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('open gesture (click selects, double-click / Enter opens)', () {
    testWidgets('remote: a click selects a folder; a double click opens it', (
      tester,
    ) async {
      final (provider, fake) = await _pumpRemote(tester, {
        '/': [_remote('/', 'etc', isDir: true)],
        '/etc': [_remote('/etc', 'hosts')],
      });

      await tester.tap(find.text('etc'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(provider.currentPath, '/');
      expect(provider.selectedEntries.map((e) => e.name), ['etc']);

      await tester.tap(find.text('etc'));
      await tester.tap(find.text('etc'));
      await tester.pump();
      await tester.pump();
      expect(provider.currentPath, '/etc');
      expect(fake.listedPaths.last, '/etc');
    });

    testWidgets("remote: double-clicking a file runs the menu's Open", (
      tester,
    ) async {
      await _pumpRemote(tester, {
        '/': [_remote('/', 'photo.png', size: 10)],
      });

      await tester.tap(find.text('photo.png'));
      await tester.tap(find.text('photo.png'));
      await tester.pumpAndSettle();
      // Open on a binary file offers the external application, exactly as
      // the context menu's Open does.
      expect(find.text('Cannot edit in-app'), findsOneWidget);
    });

    testWidgets('local: a double click opens a folder', (tester) async {
      final provider = await _pumpLocal(tester, [
        _local('/files', 'docs', isDir: true),
      ]);
      await tester.tap(find.text('docs'));
      await tester.tap(find.text('docs'));
      await tester.pump();
      expect(provider.currentPath, '/files/docs');
    });
  });

  group('keyboard flow across folders', () {
    testWidgets('remote: Enter, Enter goes two levels deep with a slow '
        'listing; the table keeps focus while loading', (tester) async {
      const latency = Duration(milliseconds: 50);
      final (provider, fake) = await _pumpRemote(tester, {
        '/': [_remote('/', 'a', isDir: true)],
        '/a': [_remote('/a', 'b', isDir: true), _remote('/a', 'z.txt')],
        '/a/b': [_remote('/a/b', 'deep.txt')],
      }, latency: latency);
      final focus = tester
          .widget<Focus>(find.byKey(const ValueKey('ys-file-table-focus')))
          .focusNode!;

      await tester.tap(find.text('a'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byType(FCircularProgress), findsOneWidget);
      expect(focus.hasFocus, isTrue, reason: 'focus survives the loading');

      await tester.pump(latency);
      await tester.pump();
      expect(provider.currentPath, '/a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // cursor on "b"
      await tester.pump();
      await tester.pump(latency);
      await tester.pump();

      expect(provider.currentPath, '/a/b');
      expect(fake.listedPaths, ['/', '/a', '/a/b']);
      expect(focus.hasFocus, isTrue);
      expect(find.text('deep.txt'), findsOneWidget);
    });

    testWidgets('local: Enter, Enter goes two levels deep', (tester) async {
      final provider = await _pumpLocal(tester, [
        _local('/files', 'docs', isDir: true),
      ]);
      await tester.tap(find.text('docs'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.currentPath, '/files/docs');
      // The real listing never lands in the fake zone; deliver it.
      provider.setEntriesForTest([_local('/files/docs', 'old', isDir: true)]);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.currentPath, '/files/docs/old');
    });

    testWidgets('remote: the cursor stays on the same entry across a reload', (
      tester,
    ) async {
      final (provider, _) = await _pumpRemote(tester, {
        '/': [_remote('/', 'a', isDir: true), _remote('/', 'b', isDir: true)],
      });
      await tester.tap(find.text('a'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // b

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump(_pressFeedback);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.currentPath, '/b');
    });

    testWidgets('remote: Shift+Down with nothing selected selects from the '
        'cursor', (tester) async {
      final (provider, _) = await _pumpRemote(tester, {
        '/': [_remote('/', 'a'), _remote('/', 'b'), _remote('/', 'c')],
      });
      tester
          .widget<Focus>(find.byKey(const ValueKey('ys-file-table-focus')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // b
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // c
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(provider.selectedEntries.map((e) => e.name).toSet(), {'b', 'c'});
    });
  });

  group('dates', () {
    testWidgets('a remote entry without mtime shows "—" and sorts last', (
      tester,
    ) async {
      final (provider, _) = await _pumpRemote(tester, {
        '/': [
          SftpEntry(
            name: 'nodate',
            path: '/nodate',
            isDirectory: false,
            size: 1,
            modifiedAt: null,
          ),
          _remote('/', 'dated'),
        ],
      }, host: _host());
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pump();
      expect(find.text('—'), findsWidgets);

      for (final ascending in [true, false]) {
        provider.setSort(EntrySortColumn.modified, ascending: ascending);
        expect(
          provider.filteredEntries.last.name,
          'nodate',
          reason: 'ascending: $ascending',
        );
      }
    });

    testWidgets('"Today" turns into the date after midnight without any '
        'interaction', (tester) async {
      fileDateNow = () => DateTime(2026, 1, 1, 23, 59);
      addTearDown(() => fileDateNow = DateTime.now);
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = LocalFilePanelProvider.forTest('/files');
      addTearDown(provider.dispose);
      await tester.pumpWidget(ysTestApp(LocalFilePanel(provider: provider)));
      await tester.pump();
      provider.setEntriesForTest([
        LocalEntry(
          name: 'late.txt',
          path: '/files/late.txt',
          isDirectory: false,
          size: 1,
          modifiedAt: DateTime(2026, 1, 1, 23, 0),
          permissions: '-rw-r--r--',
        ),
      ]);
      await tester.pump();
      expect(find.text('Today 23:00'), findsOneWidget);

      fileDateNow = () => DateTime(2026, 1, 2, 0, 1);
      await tester.pump(const Duration(minutes: 2)); // the midnight timer
      await tester.pump();
      expect(find.text('Today 23:00'), findsNothing);
      expect(find.text('1/1/2026, 23:00'), findsOneWidget);
    });
  });

  group('menu lifetime', () {
    testWidgets('an open entry menu closes with its panel', (tester) async {
      await _pumpLocal(tester, [_local('/files', 'a.txt')]);
      await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsOneWidget);

      await tester.pumpWidget(ysTestApp(const SizedBox()));
      await tester.pumpAndSettle();
      expect(find.text('Copy path'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('pane minimum', () {
    testWidgets('900×600: dragging the gutter to either end stops at 35 % '
        'and never overflows', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notifier = ValueNotifier<bool>(false);
      addTearDown(notifier.dispose);
      final storage = StorageService();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SshService>(create: (_) => SshService(storage)),
            ChangeNotifierProvider(create: (_) => HostProvider(storage)),
          ],
          child: ysTestApp(
            Row(
              children: [
                const SizedBox(width: 200),
                Expanded(
                  child: DualPanelSftpScreen(connectionNotifier: notifier),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      double gutter() => tester.getCenter(find.byTooltip('Copy →')).dx;
      for (final dx in [-600.0, 900.0]) {
        await tester.dragFrom(Offset(gutter(), 60), Offset(dx, 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'drag $dx');
        final left = tester.getSize(find.byType(LocalFilePanel)).width;
        final right = 700 - left - 36;
        expect(left, greaterThanOrEqualTo(0.35 * 700 - 18 - 1));
        expect(right, greaterThanOrEqualTo(0.35 * 700 - 18 - 1));
      }
    });
  });

  group('SftpScreen (single host)', () {
    testWidgets('lists the folder, keeps its actions, and Enter opens a '
        'folder', (tester) async {
      final sftp = _FakeSftp({
        '/': [
          _name('.'),
          _name('var', dir: true),
          _name('notes.txt', size: 2048),
        ],
        '/var': [_name('..', dir: true), _name('log', dir: true)],
      });
      await tester.pumpWidget(
        Provider<SshService>.value(
          value: _FakeSsh(sftp),
          child: ysTestApp(SftpScreen(host: _host(label: 'web-01'))),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('var'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('.'), findsNothing);
      for (final tip in ['Go up', 'Refresh', 'Close', 'Download']) {
        expect(find.byTooltip(tip), findsWidgets, reason: tip);
      }
      expect(find.text('Upload'), findsOneWidget);

      await tester.tap(find.text('var'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(sftp.listed.last, '/var');
      expect(find.text('log'), findsOneWidget);
    });

    testWidgets('Enter, Enter goes two levels deep with a slow listing', (
      tester,
    ) async {
      const latency = Duration(milliseconds: 50);
      final sftp = _FakeSftp({
        '/': [_name('var', dir: true)],
        '/var': [_name('..', dir: true), _name('log', dir: true)],
        '/var/log': [_name('syslog', size: 1)],
      }, latency: latency);
      await tester.pumpWidget(
        Provider<SshService>.value(
          value: _FakeSsh(sftp),
          child: ysTestApp(SftpScreen(host: _host(label: 'web-01'))),
        ),
      );
      await tester.pump();
      await tester.pump(latency);
      await tester.pump();

      await tester.tap(find.text('var'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(latency);
      await tester.pump();
      // ".." is first; move to "log".
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(latency);
      await tester.pump();

      expect(sftp.listed, ['/', '/var', '/var/log']);
      expect(find.text('syslog'), findsOneWidget);
    });

    testWidgets('900×600 with a 60-char host label and file name', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sftp = _FakeSftp({
        '/': [_name('${'f' * 56}.txt', size: 99999999)],
      });
      await tester.pumpWidget(
        Provider<SshService>.value(
          value: _FakeSsh(sftp),
          child: ysTestApp(SftpScreen(host: _host(label: 'w' * 60))),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
