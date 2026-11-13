import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/terminal_themes.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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

  test('YourSSH Amber leads the catalog and is the fallback theme', () {
    expect(kDefaultTerminalTheme, 'YourSSH Amber');
    expect(kTerminalThemes.first.name, 'YourSSH Amber');
    expect(kTerminalThemes[1].name, 'YourSSH Dark');
    expect(terminalThemeByName('nope'), kTerminalThemes.first.data);
  });

  test('YourSSH Amber uses the Amber Brand tokens', () {
    final t = terminalThemeByName('YourSSH Amber');
    expect(t.background, YsColors.terminalSurface);
    expect(t.cursor, YsColors.primary);
    expect(t.selection, YsColors.primary.withAlpha(0x55));
    expect(t.foreground, const Color(0xFFE7E5E4));
    expect(t.searchHitBackground, YsColors.primary);
    expect(t.searchHitBackgroundCurrent, YsColors.accentText);
    expect(t.searchHitForeground, YsColors.terminalSurface);
  });

  test('catalog contains the nine added themes', () {
    expect(kTerminalThemes.length, 46);
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
