import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double ratio(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  // Alpha-blended border over background (documented for the border token).
  test('border blends over background', () {
    final b = Color.alphaBlend(YsColors.border, YsColors.background);
    expect(b.a, 1.0);
  });

  void check(String name, Color fg, Color bg, double min) {
    test('$name >= $min', () {
      final r = ratio(fg, bg);
      // ignore: avoid_print
      print('CONTRAST $name = ${r.toStringAsFixed(2)}');
      expect(r, greaterThanOrEqualTo(min));
    });
  }

  for (final e in {
    'background': YsColors.background,
    'card': YsColors.card,
    'secondary': YsColors.secondary,
    'chrome': YsColors.chrome,
  }.entries) {
    check('foreground on ${e.key}', YsColors.foreground, e.value, 4.5);
  }
  check('mutedForeground on background', YsColors.mutedForeground,
      YsColors.background, 4.5);
  check('mutedForeground on card', YsColors.mutedForeground, YsColors.card, 4.5);
  check('primaryForeground on primary', YsColors.primaryForeground,
      YsColors.primary, 4.5);
  check('accentText on background', YsColors.accentText, YsColors.background, 4.5);
  check('primary on background', YsColors.primary, YsColors.background, 3.0);
  check('ok on card', YsColors.ok, YsColors.card, 3.0);
  check('error on card', YsColors.error, YsColors.card, 3.0);
}
