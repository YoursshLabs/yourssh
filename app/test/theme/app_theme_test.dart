import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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

  group('palette tokens', () {
    test('AppColors alias the Amber Brand tokens', () {
      expect(AppColors.bg, YsColors.background);
      expect(AppColors.sidebar, YsColors.sidebar);
      expect(AppColors.card, YsColors.card);
      expect(AppColors.cardHover, YsColors.secondary);
      expect(AppColors.border, YsColors.border);
      expect(AppColors.accent, YsColors.primary);
      expect(AppColors.accentDim, const Color(0xFFE87C08));
      expect(AppColors.textPrimary, YsColors.foreground);
      expect(AppColors.textSecondary, YsColors.mutedForeground);
      expect(AppColors.textTertiary, const Color(0xFF857E79));
      expect(AppColors.red, YsColors.error);
      expect(AppColors.success, YsColors.ok);
      expect(AppColors.warning, YsColors.warn);
      expect(AppColors.offline, YsColors.off);
    });

    test('MobileColors alias the Amber Brand tokens', () {
      expect(MobileColors.accent, YsColors.primary);
      expect(MobileColors.accentSoft, const Color(0xFF2A2010));
      expect(MobileColors.bg, YsColors.background);
      expect(MobileColors.surface, YsColors.card);
      expect(MobileColors.surfaceAlt, YsColors.chrome);
      expect(MobileColors.border, YsColors.border);
      expect(MobileColors.borderSoft, const Color(0x14FFEBD2));
      expect(MobileColors.textPrimary, YsColors.foreground);
      expect(MobileColors.textMuted, YsColors.mutedForeground);
      expect(MobileColors.textFaint, const Color(0xFF857E79));
      expect(MobileColors.green, YsColors.ok);
      expect(MobileColors.red, YsColors.error);
      expect(MobileColors.yellow, YsColors.warn);
      expect(MobileColors.fieldFill, YsColors.secondary);
    });
  });
}
