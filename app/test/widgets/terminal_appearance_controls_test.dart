import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/widgets/terminal_appearance_controls.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(SettingsProvider settings,
      {AppearanceControlsLayout layout = AppearanceControlsLayout.vertical}) {
    return ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TerminalAppearanceControls(layout: layout),
          ),
        ),
      ),
    );
  }

  testWidgets('renders all three controls', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('rows layout renders the same controls', (tester) async {
    await tester.pumpWidget(
        wrap(SettingsProvider(), layout: AppearanceControlsLayout.rows));
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
  });

  testWidgets('dragging slider updates fontSize', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(wrap(settings));
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pump();
    expect(settings.fontSize, greaterThan(13));
  });

  testWidgets('selecting Custom… shows the custom font field', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    expect(find.text('Custom font name'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Apply saves the custom font name', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(wrap(settings));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hack Nerd Font');
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(settings.terminalFont, 'Hack Nerd Font');
  });

  testWidgets('non-bundled font prefills the custom field', (tester) async {
    // SettingsProvider._load() reads prefs async, so seed the mock store
    // instead of assigning the field (load would overwrite it).
    SharedPreferences.setMockInitialValues({'terminalFont': 'My Font'});
    final settings = SettingsProvider();
    await tester.pumpWidget(wrap(settings));
    await tester.pumpAndSettle();
    expect(find.text('Custom font name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'My Font'), findsOneWidget);
  });
}
