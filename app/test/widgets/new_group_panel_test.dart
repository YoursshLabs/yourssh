import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/new_group_panel.dart';

import '../helpers/ys_test_app.dart';

Future<HostProvider> _pump(WidgetTester t, VoidCallback onClose,
    {List<String> groups = const []}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(900, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late HostProvider hp;
  await t.runAsync(() async {
    hp = HostProvider(StorageService());
    await hp.ready;
    for (final g in groups) {
      await hp.addGroup(g);
    }
  });
  await t.pumpWidget(ChangeNotifierProvider<HostProvider>.value(
    value: hp,
    child: ysTestApp(Row(children: [
      const Spacer(),
      NewGroupPanel(onClose: onClose),
    ])),
  ));
  await t.pumpAndSettle();
  return hp;
}

Finder get _field => find.descendant(
    of: find.byKey(const Key('new-group-name')),
    matching: find.byType(EditableText));

void main() {
  testWidgets('smoke: title, close, autofocused field, save button',
      (t) async {
    var closed = 0;
    await _pump(t, () => closed++);
    expect(find.text('New Group'), findsOneWidget);
    expect(find.text('Group name'), findsOneWidget);
    expect(find.text('Save group'), findsOneWidget);
    expect(t.widget<EditableText>(_field).focusNode.hasFocus, isTrue,
        reason: 'name field autofocuses');
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(closed, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('Save with an empty name shows the required error', (t) async {
    var closed = 0;
    await _pump(t, () => closed++);
    await t.tap(find.text('Save group'));
    await t.pumpAndSettle();
    expect(find.text('Group name is required'), findsOneWidget);
    expect(closed, 0);
  });

  testWidgets('Enter in the name field saves the group', (t) async {
    var closed = 0;
    final hp = await _pump(t, () => closed++);
    await t.enterText(_field, 'Staging');
    await t.testTextInput.receiveAction(TextInputAction.done);
    // Saving shows a spinner until the host screen removes the panel.
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump();
    expect(hp.pinnedGroups, ['Staging']);
    expect(closed, 1);
  });

  testWidgets('duplicate name is rejected', (t) async {
    var closed = 0;
    await _pump(t, () => closed++, groups: ['Prod']);
    await t.enterText(_field, 'prod');
    await t.tap(find.text('Save group'));
    await t.pumpAndSettle();
    expect(find.text('Group "prod" already exists'), findsOneWidget);
    expect(closed, 0);
  });

  testWidgets('long name does not overflow at 900x600', (t) async {
    await _pump(t, () {});
    await t.enterText(_field, List.filled(60, 'g').join());
    await t.tap(find.text('Save group'));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
  });
}
