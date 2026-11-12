import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/widgets/terminal_appearance_controls.dart';
import 'package:yourssh/widgets/theme_picker.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../helpers/ys_test_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(SettingsProvider settings,
      {AppearanceControlsLayout layout = AppearanceControlsLayout.vertical}) {
    return ChangeNotifierProvider.value(
      value: settings,
      child: ysTestApp(
        SingleChildScrollView(
          child: TerminalAppearanceControls(layout: layout),
        ),
      ),
    );
  }

  testWidgets('renders all three controls', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('Font size: 13pt'), findsOneWidget);
    expect(find.text('Terminal font'), findsOneWidget);
    expect(find.byType(FSlider), findsOneWidget);
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
    await tester.drag(find.byType(FSlider), const Offset(100, 0));
    await tester.pump();
    expect(settings.fontSize, greaterThan(13));
  });

  testWidgets(
      'vertical layout: color theme value sits inline, right-aligned with label',
      (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    await tester.pumpAndSettle();

    final labelRect = tester.getRect(find.text('Color theme'));
    final buttonRect = tester.getRect(find.byType(ThemePickerButton));
    final panelRect = tester.getRect(find.byType(TerminalAppearanceControls));

    // Same row: vertical centers line up.
    expect(buttonRect.center.dy, moreOrLessEquals(labelRect.center.dy, epsilon: 1));
    // Right-aligned within the panel.
    expect(buttonRect.right, moreOrLessEquals(panelRect.right, epsilon: 1));
  });

  testWidgets('font options render in their own typeface', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    await tester.tap(find.byKey(const Key('terminal-font-select')));
    await tester.pumpAndSettle();

    // The closed field shows the selected value too, so look for any Text
    // (the option row) carrying the typeface.
    bool anyOptionWith(String label, String family) => find
        .byWidgetPredicate((w) =>
            w is Text && w.data == label && w.style?.fontFamily == family)
        .evaluate()
        .isNotEmpty;

    for (final font in kBundledTerminalFonts.where((f) => f != 'monospace')) {
      expect(anyOptionWith(font, font), isTrue,
          reason: '"$font" option should preview its own font');
    }
    // 'System Default' previews the generic monospace family.
    expect(anyOptionWith('System Default', 'monospace'), isTrue);
  });

  testWidgets('selecting Custom… shows the custom font field', (tester) async {
    await tester.pumpWidget(wrap(SettingsProvider()));
    await tester.tap(find.byKey(const Key('terminal-font-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    expect(find.text('Custom font name'), findsOneWidget);
    expect(find.byKey(const Key('custom-font-field')), findsOneWidget);
  });

  testWidgets('Apply saves the custom font name', (tester) async {
    final settings = SettingsProvider();
    await tester.pumpWidget(wrap(settings));
    await tester.tap(find.byKey(const Key('terminal-font-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-font-field')), 'Hack Nerd Font');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
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
    expect(find.widgetWithText(FTextField, 'My Font'), findsOneWidget);
  });
}
