import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/widgets/broadcast_toolbar.dart';

void main() {
  Widget wrap(TerminalLayoutProvider layout) {
    return ChangeNotifierProvider.value(
      value: layout,
      child: const MaterialApp(home: Scaffold(body: BroadcastToolbar())),
    );
  }

  testWidgets('tune button toggles the terminal config panel', (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout));

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, true);

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, false);
  });

  testWidgets('opening config panel from toolbar closes snippets panel',
      (tester) async {
    final layout = TerminalLayoutProvider();
    await tester.pumpWidget(wrap(layout));

    await tester.tap(find.byTooltip('Toggle Snippets Panel'));
    await tester.pump();
    expect(layout.snippetsPanelVisible, true);

    await tester.tap(find.byTooltip('Toggle Terminal Settings'));
    await tester.pump();
    expect(layout.configPanelVisible, true);
    expect(layout.snippetsPanelVisible, false);
  });
}
