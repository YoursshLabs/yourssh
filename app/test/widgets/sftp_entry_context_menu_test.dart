// app/test/widgets/sftp_entry_context_menu_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/widgets/sftp_entry_context_menu.dart';

final _file = SftpEntry(
  name: 'notes.txt',
  path: '/home/u/notes.txt',
  isDirectory: false,
  size: 10,
  modifiedAt: DateTime(2026),
);

final _dir = SftpEntry(
  name: 'src',
  path: '/home/u/src',
  isDirectory: true,
  size: 0,
  modifiedAt: DateTime(2026),
);

const _apps = [
  AppOption(name: 'VS Code', executablePath: '/usr/bin/code', isDefault: true),
  AppOption(name: 'gedit', executablePath: '/usr/bin/gedit', isDefault: false),
];

Widget _wrap({
  required SftpEntry entry,
  VoidCallback? onView,
  VoidCallback? onEdit,
  Future<List<AppOption>> Function()? loadApps,
  void Function(AppOption)? onOpenWithApp,
  VoidCallback? onChooseApp,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SftpEntryContextMenu(
        entry: entry,
        onOpen: () {},
        onView: onView,
        onEdit: onEdit,
        loadApps: loadApps,
        onOpenWithApp: onOpenWithApp,
        onChooseApp: onChooseApp,
        onRename: () {},
        onDelete: () {},
        child: Text(entry.name),
      ),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, String text) async {
  await tester.tap(find.text(text), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right-click shows View, Edit, Open with for files',
      (tester) async {
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    expect(find.text('View'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Open with'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
  });

  testWidgets('directories show Enter and no Open with', (tester) async {
    await tester.pumpWidget(_wrap(entry: _dir));
    await _rightClick(tester, 'src');

    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('View'), findsNothing);
    expect(find.text('Open with'), findsNothing);
  });

  testWidgets('hovering "Open with" opens the submenu without a click',
      (tester) async {
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    // Simulate a mouse hover over the "Open with" submenu button.
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Open with')));
    await tester.pumpAndSettle();

    expect(find.text('VS Code'), findsOneWidget);
    expect(find.text('gedit'), findsOneWidget);
    expect(find.text('Choose…'), findsOneWidget);
  });

  testWidgets('tapping an app item calls onOpenWithApp', (tester) async {
    AppOption? picked;
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (a) => picked = a,
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VS Code'));
    await tester.pumpAndSettle();

    expect(picked?.executablePath, '/usr/bin/code');
  });

  testWidgets('tapping Choose… calls onChooseApp', (tester) async {
    var chooseCalled = false;
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () => chooseCalled = true,
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose…'));
    await tester.pumpAndSettle();

    expect(chooseCalled, isTrue);
  });

  testWidgets('tapping View calls onView', (tester) async {
    var viewCalled = false;
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () => viewCalled = true,
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(viewCalled, isTrue);
  });

  testWidgets('default app shows a default chip', (tester) async {
    await tester.pumpWidget(_wrap(
      entry: _file,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');
    await tester.tap(find.text('Open with'));
    await tester.pumpAndSettle();

    expect(find.text('default'), findsOneWidget); // VS Code is default
  });
}
