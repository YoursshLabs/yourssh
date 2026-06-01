import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/app_theme.dart';

void main() {
  group('AppColors.fromHex', () {
    test('parses #rrggbb with full opacity', () {
      expect(AppColors.fromHex('#ef4444'), const Color(0xFFEF4444));
    });

    test('parses without leading hash', () {
      expect(AppColors.fromHex('22c55e'), const Color(0xFF22C55E));
    });

    test('parses #aarrggbb', () {
      expect(AppColors.fromHex('#8022c55e'), const Color(0x8022C55E));
    });

    test('returns fallback for malformed input instead of throwing', () {
      expect(AppColors.fromHex('not-a-color'), AppColors.textSecondary);
      expect(AppColors.fromHex('#fff'), AppColors.textSecondary); // wrong length
      expect(
        AppColors.fromHex('zzzzzz', fallback: AppColors.red),
        AppColors.red,
      );
    });

    test('every tabColors entry parses to a non-fallback color', () {
      for (final (_, hex) in AppColors.tabColors) {
        expect(AppColors.fromHex(hex), isNot(AppColors.textSecondary));
      }
    });
  });
}
