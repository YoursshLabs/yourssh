import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/widgets/terminal_config_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap({VoidCallback? onClose}) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Row(children: [TerminalConfigPanel(onClose: onClose)]),
        ),
      ),
    );
  }

  testWidgets('renders title and appearance controls', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
  });

  testWidgets('close button fires onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(wrap(onClose: () => closed = true));
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, true);
  });

  testWidgets('panel is 340 wide', (tester) async {
    await tester.pumpWidget(wrap());
    final size = tester.getSize(find.byType(TerminalConfigPanel));
    expect(size.width, 340);
  });
}
