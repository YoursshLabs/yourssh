import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

void main() {
  test('forui theme uses Amber tokens', () {
    expect(ysThemeData().colors.primary, YsColors.primary);
    expect(ysThemeData().colors.background, YsColors.background);
    expect(ysThemeDataTouch().colors.primary, YsColors.primary);
    expect(ysThemeData().typography.body.fontFamily, kYsFontFamily);
  });

  test('material theme uses Amber tokens', () {
    final t = ysMaterialTheme();
    expect(t.colorScheme.primary, YsColors.primary);
    expect(t.textTheme.bodyMedium!.fontFamily, 'Inter');
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, YsColors.background);
    expect(t.dividerColor, YsColors.border);
  });
}
