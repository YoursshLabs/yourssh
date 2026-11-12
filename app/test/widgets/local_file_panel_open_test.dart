// Opening a file from the local panel: executables need a confirm first.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/local_entry.dart';
import 'package:yourssh/providers/local_file_panel_provider.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh/widgets/local_file_panel.dart';

LocalEntry _entry(String name) => LocalEntry(
      name: name,
      path: '/files/$name',
      isDirectory: false,
      size: 10,
      modifiedAt: DateTime(2026),
      permissions: '-rw-r--r--',
    );

const _settle = Duration(milliseconds: 300);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalFilePanelProvider provider;
  late List<String> launched;

  setUp(() {
    provider = LocalFilePanelProvider.forTest('/files');
    launched = [];
  });

  tearDown(() => provider.dispose());

  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: ysRootBuilder,
        home: Scaffold(
          body: LocalFilePanel(
            provider: provider,
            platform: 'macos',
            launcher: (path) async {
              launched.add(path);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    provider.setEntriesForTest([_entry('run.command'), _entry('notes.txt')]);
    await tester.pump();
  }

  Future<void> doubleTap(WidgetTester tester, String name) async {
    final target = find.text(name);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pump(_settle);
  }

  testWidgets('executable: confirm shown, Cancel launches nothing',
      (tester) async {
    await pumpPanel(tester);
    await doubleTap(tester, 'run.command');
    expect(find.text('Run this file?'), findsOneWidget);
    expect(find.textContaining('run.command can run programs'),
        findsOneWidget);
    expect(launched, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pump(_settle);
    await tester.pump(_settle);
    expect(find.text('Run this file?'), findsNothing);
    expect(launched, isEmpty);
  });

  testWidgets('executable: "Open anyway" launches', (tester) async {
    await pumpPanel(tester);
    await doubleTap(tester, 'run.command');
    await tester.tap(find.text('Open anyway'));
    await tester.pump(_settle);
    await tester.pump(_settle);
    expect(launched, ['/files/run.command']);
  });

  testWidgets('executable: Cancel is the focused default', (tester) async {
    await pumpPanel(tester);
    await doubleTap(tester, 'run.command');
    // Enter activates the focused (safe) choice = Cancel.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(_settle);
    await tester.pump(_settle);
    expect(launched, isEmpty);
    expect(find.text('Run this file?'), findsNothing);
  });

  testWidgets('plain file launches without a confirm', (tester) async {
    await pumpPanel(tester);
    await doubleTap(tester, 'notes.txt');
    expect(find.text('Run this file?'), findsNothing);
    expect(launched, ['/files/notes.txt']);
  });
}
