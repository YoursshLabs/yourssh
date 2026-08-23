import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/theme/mobile_tokens.dart';

void main() {
  test('mobile theme primary is amber', () {
    expect(buildMobileTheme().colorScheme.primary, MobileColors.accent);
    expect(buildMobileTheme().brightness, Brightness.dark);
  });
  test('section label token is faint + spaced', () {
    final s = MobileTokens.sectionLabel();
    expect(s.color, MobileColors.textFaint);
    expect(s.letterSpacing, 1.0);
  });
  testWidgets('mono style uses a non-null fontFamily', (t) async {
    expect(mobileMono(size: 12).fontFamily, isNotNull);
  });
}
