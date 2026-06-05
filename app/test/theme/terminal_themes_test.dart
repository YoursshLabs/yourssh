import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/terminal_themes.dart';

void main() {
  // xterm paints the selection rectangle ON TOP of the text layer, so a
  // fully opaque selection color hides the selected text entirely
  // (issue #40). Every theme must use a semi-transparent selection color.
  test('every terminal theme has a semi-transparent selection color', () {
    for (final entry in kTerminalThemes) {
      final alpha = entry.data.selection.a;
      expect(alpha, lessThan(1.0),
          reason: '${entry.name}: opaque selection hides selected text');
      expect(alpha, greaterThan(0.2),
          reason: '${entry.name}: selection too faint to see');
    }
  });

  test('terminalThemeByName falls back to the first theme', () {
    expect(terminalThemeByName('No Such Theme'), kTerminalThemes.first.data);
  });

  test('theme names are unique', () {
    final names = kTerminalThemes.map((e) => e.name).toList();
    expect(names.toSet().length, names.length);
  });

  test('catalog contains the nine added themes', () {
    expect(kTerminalThemes.length, 44);
    const added = [
      'Kanagawa Dragon',
      'Kanagawa Lotus',
      'Tokyo Night Day',
      'Nord Light',
      'Light Owl',
      'Flexoki Dark',
      'Flexoki Light',
      'Aura',
      'Cyberpunk',
    ];
    for (final name in added) {
      expect(kTerminalThemeNames, contains(name));
    }
  });
}
