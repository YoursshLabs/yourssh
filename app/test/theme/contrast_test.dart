import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _ratio(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  final cases = <String, Color>{
    'AppColors.textTertiary': AppColors.textTertiary,
    'MobileColors.textFaint': MobileColors.textFaint,
  };
  for (final e in cases.entries) {
    for (final bg in {
      'card': YsColors.card,
      'background': YsColors.background,
    }.entries) {
      test('${e.key} on ${bg.key} >= 4.5', () {
        expect(_ratio(e.value, bg.value), greaterThanOrEqualTo(4.5));
      });
    }
  }
}
