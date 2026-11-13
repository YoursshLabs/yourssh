import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/import_panel.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show FCheckbox;

import '../helpers/ys_test_app.dart';

Future<HostProvider> _pump(WidgetTester t, VoidCallback onClose,
    {List<Host> existing = const [], double height = 1000}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = Size(900, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  late HostProvider hp;
  await t.runAsync(() async {
    hp = HostProvider(StorageService());
    await hp.ready;
    for (final h in existing) {
      await hp.addHost(h);
    }
  });
  await t.pumpWidget(ChangeNotifierProvider<HostProvider>.value(
    value: hp,
    child: ysTestApp(Row(children: [
      const Spacer(),
      ImportPanel(onClose: onClose),
    ])),
  ));
  await t.pumpAndSettle();
  return hp;
}

Future<void> _openCsvPaste(WidgetTester t, String csv) async {
  await t.tap(find.text('CSV'));
  await t.pumpAndSettle();
  await t.tap(find.text('Paste text'));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('import-paste-field')), csv);
  await t.tap(find.text('Parse'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('smoke: every source, close, and back to the picker',
      (t) async {
    var closed = 0;
    await _pump(t, () => closed++);
    expect(find.text('Import Hosts'), findsOneWidget);
    for (final def in ImportSourceDef.all) {
      expect(find.text(def.label), findsOneWidget, reason: def.label);
    }
    await t.tap(find.text('PuTTY'));
    await t.pumpAndSettle();
    expect(find.text('Import from PuTTY'), findsOneWidget);
    expect(find.text('From file'), findsOneWidget);
    expect(find.text('Paste text'), findsOneWidget);
    expect(find.textContaining('Choose file (.reg, .txt)'), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('Import Hosts'), findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(closed, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('paste, preview, deselect, import', (t) async {
    var closed = 0;
    final hp = await _pump(t, () => closed++);
    await _openCsvPaste(t, 'host,label\na.x,A\nb.x,B');
    expect(find.text('2 hosts found'), findsOneWidget);
    expect(find.text('IMPORT 2 HOSTS'), findsOneWidget);

    await t.tap(find.byType(FCheckbox).first);
    await t.pumpAndSettle();
    expect(find.text('IMPORT 1 HOST'), findsOneWidget);

    await t.tap(find.text('IMPORT 1 HOST'));
    await t.pumpAndSettle();
    expect(hp.allHosts.map((h) => h.host), ['b.x']);
    expect(closed, 1);
  });

  testWidgets('duplicates are skipped until toggled to overwrite',
      (t) async {
    final hp = await _pump(t, () {},
        existing: [Host(label: 'old', host: 'a.x', username: 'root')]);
    await _openCsvPaste(t, 'host,label,username\na.x,New,root');
    expect(find.text('Skip dup'), findsOneWidget);
    expect(find.text('IMPORT 0 HOSTS'), findsOneWidget);
    await t.tap(find.text('Skip dup'));
    await t.pumpAndSettle();
    expect(find.text('Overwrite'), findsOneWidget);
    expect(find.text('IMPORT 1 HOST'), findsOneWidget);
    await t.tap(find.text('IMPORT 1 HOST'));
    await t.pumpAndSettle();
    expect(hp.allHosts.single.label, 'New');
  });

  testWidgets('bad input shows the parse error, skipped rows are listed',
      (t) async {
    await _pump(t, () {});
    await _openCsvPaste(t, 'label\nfoo');
    expect(find.text("CSV missing required 'host' column"), findsOneWidget);
  });

  testWidgets('long labels do not overflow at 900x600', (t) async {
    await _pump(t, () {},
        height: 600, existing: [Host(label: 'x', host: 'a.x', username: 'root')]);
    final long = 'h' * 60;
    await _openCsvPaste(
        t, 'host,label,username\na.x,$long,root\n${'z' * 60}.example,$long,u');
    expect(find.textContaining('hosts found'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
