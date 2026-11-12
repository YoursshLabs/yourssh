import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/widgets/recording_library_screen.dart';
import 'package:yourssh/widgets/recording_player_widget.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

const _cast = '{"version":2,"width":80,"height":24}\n'
    '[0.5,"o","hello\\r\\n"]\n'
    '[1.5,"o","world\\r\\n"]\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late RecordingProvider provider;
  late SettingsProvider settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('rec_lib_');
    provider = RecordingProvider(RecordingService(), getPath: () => tmp.path);
    settings = SettingsProvider();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String addCast(String host, String name) {
    final dir = Directory('${tmp.path}/$host')..createSync(recursive: true);
    final f = File('${dir.path}/$name')..writeAsStringSync(_cast);
    return f.path;
  }

  Widget app(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: provider),
      ChangeNotifierProvider.value(value: settings),
    ],
    child: ysTestApp(child),
  );

  /// Lets real file IO finish (the test clock is fake) and delivers it.
  Future<void> realIo(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.runAsync(provider.refreshLibrary);
    await tester.pumpWidget(app(const RecordingLibraryScreen()));
    await realIo(tester);
    await tester.pump();
  }

  testWidgets('empty library shows the hint', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('Recording Library'), findsOneWidget);
    expect(find.text('No recordings yet'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });

  testWidgets('lists recordings grouped by host with play and delete',
      (tester) async {
    addCast('web-1', 'session_2026-01-02_03-04-05.cast');
    addCast('web-1', 'session_2026-01-03_03-04-05.cast');
    await pumpLibrary(tester);

    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('2 recordings'), findsOneWidget);
    expect(find.text('2026-01-02 03:04'), findsOneWidget);
    expect(find.byTooltip('Play recording'), findsNWidgets(2));
    expect(find.byTooltip('Delete'), findsNWidgets(2));
  });

  testWidgets('in-tile buttons fire: play opens the player, close dismisses',
      (tester) async {
    final path = addCast('web-1', 'session_2026-01-02_03-04-05.cast');
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('Play recording').first);
    await tester.pump();
    expect(find.byType(RecordingPlayerWidget), findsOneWidget);
    expect(
      tester.widget<RecordingPlayerWidget>(find.byType(RecordingPlayerWidget)).filePath,
      path,
    );
    expect(find.text('session_2026-01-02_03-04-05.cast'), findsOneWidget);

    await realIo(tester);
    await tester.tap(find.byTooltip('Close player'));
    await tester.pump();
    expect(find.byType(RecordingPlayerWidget), findsNothing);
    await tester.pump(const Duration(milliseconds: 200)); // tap timer
  });

  testWidgets('in-tile delete confirms with Cancel focused, then deletes',
      (tester) async {
    final path = addCast('web-1', 'session_2026-01-02_03-04-05.cast');
    await pumpLibrary(tester);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete recording?'), findsOneWidget);
    final cancel = tester.widget<FButton>(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(FButton)),
    );
    expect(cancel.autofocus, isTrue, reason: 'safe choice holds focus');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(File(path).existsSync(), isTrue);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pump();
    await realIo(tester);
    await tester.pumpAndSettle();
    expect(File(path).existsSync(), isFalse);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('900x600 with a 60-char host folder and open player does not overflow',
      (tester) async {
    addCast('h' * 60, 'session_2026-01-02_03-04-05.cast');
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpLibrary(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Play recording'));
    await tester.pump();
    await realIo(tester);
    await tester.pump(const Duration(milliseconds: 200)); // tap timer
    expect(tester.takeException(), isNull);
  });

  group('RecordingPlayerWidget', () {
    testWidgets('loads, plays, pauses, changes speed and shows progress',
        (tester) async {
      final path = addCast('web-1', 'p.cast');
      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(RecordingPlayerWidget(filePath: path)));
      await realIo(tester);
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('00:01'), findsOneWidget, reason: 'total 1.5 s');
      expect(find.byType(FDeterminateProgress), findsOneWidget);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);

      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('Play'), findsOneWidget, reason: 'ended');

      await tester.tap(find.byKey(const ValueKey('player-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2.0x').last);
      await tester.pumpAndSettle();
      expect(find.text('2.0x'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unreadable file shows the error', (tester) async {
      await tester.pumpWidget(
        app(RecordingPlayerWidget(filePath: '${tmp.path}/missing.cast')),
      );
      await realIo(tester);
      await tester.pump();
      expect(find.textContaining('PathNotFound'), findsOneWidget);
    });
  });
}
