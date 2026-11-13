import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final html = File('assets/monaco_editor.html').readAsStringSync();

  test('defines the yourssh-amber theme from the design tokens', () {
    expect(html, contains("defineTheme('yourssh-amber'"));
    expect(html, contains('#0E0C0A')); // terminalSurface background
    expect(html, contains('#F3A231')); // primary cursor
    expect(html, contains('#F3A23155')); // primary selection @ 0x55
    expect(html, contains('#161412')); // card gutter
    expect(html, contains('#E7E5E4')); // foreground
  });

  test('selects yourssh-amber as the default editor theme', () {
    expect(html, contains("theme: 'yourssh-amber'"));
    expect(html, isNot(contains("theme: 'vs-dark'")));
  });

  test('does not add CDN sources beyond the existing Monaco loader', () {
    final hosts = RegExp(r'https?://([^/\s"\x27]+)')
        .allMatches(html)
        .map((m) => m.group(1))
        .toSet();
    expect(hosts, {'cdn.jsdelivr.net'});
  });
}
