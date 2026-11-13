import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/plugin_status_bar_item.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';

import '../helpers/ys_test_app.dart';

void main() {
  StatusBarItem item({String? tooltip, VoidCallback? onClick}) => StatusBarItem(
    id: 'i',
    pluginId: 'p',
    label: 'Deploy ok',
    tooltip: tooltip,
    onClick: onClick,
  );

  testWidgets('renders the label and activates on tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      ysTestApp(
        Row(children: [PluginStatusBarItem(item: item(onClick: () => taps++))]),
      ),
    );
    expect(find.text('Deploy ok'), findsOneWidget);
    await tester.tap(find.text('Deploy ok'));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
  });

  testWidgets('tooltip only when the plugin supplied one', (tester) async {
    await tester.pumpWidget(
      ysTestApp(Row(children: [PluginStatusBarItem(item: item())])),
    );
    expect(find.byType(Tooltip), findsNothing);

    await tester.pumpWidget(
      ysTestApp(
        Row(children: [PluginStatusBarItem(item: item(tooltip: 'Last deploy'))]),
      ),
    );
    expect(find.byTooltip('Last deploy'), findsOneWidget);
  });
}
