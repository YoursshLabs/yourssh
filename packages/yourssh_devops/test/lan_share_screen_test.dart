import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_devops/src/screens/lan_share_screen.dart';
import 'package:yourssh_devops/src/services/lan_share_service.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'helpers/tab_to.dart';
import 'helpers/ys_test_app.dart';

class _FakeLan extends LanShareService {
  int stops = 0;
  String? shared;
  @override
  Future<String?> share(String filePath, {int port = 8765}) async {
    shared = filePath;
    return 'http://192.168.1.5:$port/d/tok/${filePath.split('/').last}';
  }

  @override
  Future<void> stop() async => stops++;
}

final _longName = '${'n' * 56}.zip';

Future<FilePickerResult?> _pick() async => FilePickerResult([
  PlatformFile(name: _longName, size: 1536, path: '/tmp/$_longName'),
]);

Widget _screen(_FakeLan svc) =>
    ysTestApp(LanShareScreen(service: svc, pickFile: _pick));

void main() {
  testWidgets('idle state shows the steps and the pick button', (tester) async {
    await tester.pumpWidget(_screen(_FakeLan()));
    await tester.pumpAndSettle();
    expect(find.text('LocalShare'), findsOneWidget);
    expect(
      find.text('Share files on your local network over HTTP.'),
      findsOneWidget,
    );
    expect(find.text('Pick a file'), findsOneWidget);
    expect(find.text('Pick File to Share'), findsOneWidget);
  });

  testWidgets('share -> URL, copy, stop', (tester) async {
    final svc = _FakeLan();
    await tester.pumpWidget(_screen(svc));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick File to Share'));
    await tester.pumpAndSettle();
    expect(svc.shared, '/tmp/$_longName');
    expect(find.text('Share URL:'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byTooltip('Copy URL'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy URL'));
    await tester.pumpAndSettle();
    expect(find.text('URL copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('Stop Sharing'));
    await tester.pumpAndSettle();
    expect(svc.stops, 1);
    expect(find.text('Pick File to Share'), findsOneWidget);
  });

  testWidgets('no overflow at 900x600 with a 60-char file name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen(_FakeLan()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Pick File to Share'));
    await tester.pumpAndSettle();
    expect(find.text(_longName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab reaches Pick File to Share', (tester) async {
    final svc = _FakeLan();
    await tester.pumpWidget(_screen(svc));
    await tester.pumpAndSettle();
    expect(
      await tabTo(tester, find.text('Pick File to Share')),
      greaterThan(0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(svc.shared, isNotNull);
  });

  testWidgets('Tab reaches Copy URL and Stop Sharing', (tester) async {
    await tester.pumpWidget(_screen(_FakeLan()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick File to Share'));
    await tester.pumpAndSettle();
    expect(await tabTo(tester, find.byTooltip('Copy URL')), greaterThan(0));
    expect(await tabTo(tester, find.text('Stop Sharing')), greaterThan(0));
  });

  testWidgets('renders under the Ys theme', (tester) async {
    await tester.pumpWidget(_screen(_FakeLan()));
    await tester.pumpAndSettle();
    expect(
      FTheme.of(tester.element(find.text('LocalShare'))).colors.primary,
      YsColors.primary,
    );
  });
}
