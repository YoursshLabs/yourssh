// app/test/widgets/entry_context_menu_test.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';
import 'package:yourssh/widgets/entry_context_menu.dart';

const _apps = [
  AppOption(name: 'VS Code', executablePath: '/usr/bin/code', isDefault: true),
  AppOption(name: 'gedit', executablePath: '/usr/bin/gedit', isDefault: false),
];

Widget _wrap({
  required String label,
  required bool isDirectory,
  VoidCallback? onView,
  VoidCallback? onEdit,
  Future<List<AppOption>> Function()? loadApps,
  void Function(AppOption)? onOpenWithApp,
  VoidCallback? onChooseApp,
  VoidCallback? onCopyToTarget,
  String? copyToTargetDisabledReason,
  VoidCallback? onEditPermissions,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EntryContextMenu(
        path: '/home/u/$label',
        isDirectory: isDirectory,
        onOpen: () {},
        onView: onView,
        onEdit: onEdit,
        loadApps: loadApps,
        onOpenWithApp: onOpenWithApp,
        onChooseApp: onChooseApp,
        onCopyToTarget: onCopyToTarget,
        copyToTargetDisabledReason: copyToTargetDisabledReason,
        onRename: () {},
        onDelete: () {},
        onRefresh: () {},
        onNewFolder: () {},
        onEditPermissions: onEditPermissions,
        child: Text(label),
      ),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, String text) async {
  await tester.tap(find.text(text), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('file menu shows all items in order', (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
      onCopyToTarget: () {},
      onEditPermissions: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    for (final item in [
      'Open', 'View', 'Edit', 'Open with', 'Copy to target directory',
      'Rename', 'Delete', 'Refresh', 'New Folder', 'Edit Permissions',
      'Copy path',
    ]) {
      expect(find.text(item), findsOneWidget, reason: 'missing $item');
    }
  });

  testWidgets('directories show Open (not Enter) and no file-only items',
      (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'src',
      isDirectory: true,
      onCopyToTarget: () {},
      onEditPermissions: () {},
    ));
    await _rightClick(tester, 'src');

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Enter'), findsNothing);
    expect(find.text('View'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Open with'), findsNothing);
    expect(find.text('Copy to target directory'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('New Folder'), findsOneWidget);
    expect(find.text('Edit Permissions'), findsOneWidget);
  });

  testWidgets('copy to target disabled with reason', (tester) async {
    var copied = false;
    await tester.pumpWidget(_wrap(
      label: 'src',
      isDirectory: true,
      onCopyToTarget: () => copied = true,
      copyToTargetDisabledReason: 'No target panel',
    ));
    await _rightClick(tester, 'src');

    expect(find.text('No target panel'), findsOneWidget);
    await tester.tap(find.text('Copy to target directory'),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(copied, isFalse);
  });

  testWidgets('copy to target enabled fires callback', (tester) async {
    var copied = false;
    await tester.pumpWidget(_wrap(
      label: 'src',
      isDirectory: true,
      onCopyToTarget: () => copied = true,
    ));
    await _rightClick(tester, 'src');
    await tester.tap(find.text('Copy to target directory'));
    await tester.pumpAndSettle();
    expect(copied, isTrue);
  });

  testWidgets('Edit Permissions hidden when callback is null',
      (tester) async {
    await tester.pumpWidget(_wrap(label: 'src', isDirectory: true));
    await _rightClick(tester, 'src');
    expect(find.text('Edit Permissions'), findsNothing);
  });

  testWidgets('hovering "Open with" opens the submenu without a click',
      (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
      onView: () {},
      onEdit: () {},
      loadApps: () async => _apps,
      onOpenWithApp: (_) {},
      onChooseApp: () {},
    ));
    await _rightClick(tester, 'notes.txt');

    // Simulate a mouse hover over the "Open with" submenu button.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
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
      label: 'notes.txt',
      isDirectory: false,
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

  testWidgets('default app shows a default chip', (tester) async {
    await tester.pumpWidget(_wrap(
      label: 'notes.txt',
      isDirectory: false,
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
