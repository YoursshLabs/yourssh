import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/settings/settings_tiles.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../helpers/ys_test_app.dart';
import 'settings_harness.dart';

void main() {
  const key = ValueKey('sw');
  late List<bool> changes;

  Future<void> pump(WidgetTester tester) async {
    changes = [];
    var value = false;
    await tester.pumpWidget(
      ysTestApp(
        StatefulBuilder(
          builder: (context, setState) => settingsTileGroup(
            children: [
              settingsSwitchTile(
                key: key,
                label: 'Label',
                description: 'Description',
                value: value,
                onChange: (v) => setState(() {
                  value = v;
                  changes.add(v);
                }),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the row gap toggles once', (tester) async {
    await pump(tester);
    final tile = find.byType(FTile);
    await tester.tapAt(
      tester.getTopLeft(tile) + Offset(3, tester.getSize(tile).height / 2),
    );
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(tester.widget<FSwitch>(find.byKey(key)).value, isTrue);
  });

  testWidgets('tapping the switch toggles once', (tester) async {
    await pump(tester);
    await tapSwitch(tester, key);
    expect(changes, [true]);
  });

  testWidgets('tapping the label toggles once', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Label'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });
}
