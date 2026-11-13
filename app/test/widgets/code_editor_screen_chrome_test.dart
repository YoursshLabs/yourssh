import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh/widgets/code_editor_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class _Service extends SftpTransferService {
  _Service() : super(SshService(StorageService()));

  @override
  Future<String?> downloadToTemp(Host host, SftpEntry entry) async {
    final dir = await Directory.systemTemp.createTemp('yourssh_chrome_test');
    final file = File('${dir.path}/${entry.name}');
    await file.writeAsBytes(utf8.encode('hello'));
    return file.path;
  }
}

final _host = Host(label: 'test', host: 'example.com', username: 'u');
SftpEntry _entry(String name) => SftpEntry(
  name: name,
  path: '/etc/$name',
  isDirectory: false,
  size: 5,
  modifiedAt: DateTime(2026),
);

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('$finder not found after pumping');
}

Future<void> _open(
  WidgetTester tester,
  String name, {
  bool readOnly = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: ysRootBuilder,
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => Provider<SftpTransferService>.value(
                value: _Service(),
                child: CodeEditorScreen(
                  host: _host,
                  entry: _entry(name),
                  readOnly: readOnly,
                ),
              ),
            ),
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await _pumpUntilFound(tester, find.byType(FTextField));
}

void main() {
  testWidgets('chrome: title, back and save are forui buttons with tooltips', (
    tester,
  ) async {
    await _open(tester, 'config.txt');

    expect(find.text('config.txt'), findsOneWidget);
    expect(find.byTooltip('Save (Ctrl+S)'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.widgetWithIcon(FButton, FLucideIcons.save), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('readOnly chrome: lock indicator, no save', (tester) async {
    await _open(tester, 'log.txt', readOnly: true);
    expect(find.byIcon(FLucideIcons.lock), findsOneWidget);
    expect(find.byTooltip('Save (Ctrl+S)'), findsNothing);
  });

  testWidgets('long file name at 900x600 does not overflow', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, '${'n' * 60}.txt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('back with unsaved edits asks to discard; Cancel stays', (
    tester,
  ) async {
    await _open(tester, 'config.txt');
    await tester.enterText(find.byType(FTextField), 'edited');
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byType(CodeEditorScreen), findsOneWidget);
  });
}
