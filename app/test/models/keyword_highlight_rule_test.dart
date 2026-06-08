import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/keyword_highlight_rule.dart';

void main() {
  group('AppKeywordHighlightRule', () {
    test('toXtermRule compiles literal pattern with escape', () {
      final rule = AppKeywordHighlightRule(
        id: '1',
        label: 'Error',
        pattern: 'error[test]',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: Colors.red,
      );
      final xterm = rule.toXtermRule();
      expect(xterm, isNotNull);
      // Literal match: "error[test]" as a string, not a char class
      expect(xterm!.pattern.hasMatch('error[test]'), isTrue);
      expect(xterm.pattern.hasMatch('errort'), isFalse);
    });

    test('toXtermRule compiles regex pattern', () {
      final rule = AppKeywordHighlightRule(
        id: '2',
        label: 'OK',
        pattern: r'\bok\b',
        isRegex: true,
        caseSensitive: false,
        enabled: true,
        foreground: Colors.green,
        background: null,
      );
      final xterm = rule.toXtermRule();
      expect(xterm, isNotNull);
      expect(xterm!.pattern.hasMatch('ok'), isTrue);
      expect(xterm.pattern.hasMatch('working'), isFalse);
    });

    test('toXtermRule returns null when both foreground and background are null', () {
      final rule = AppKeywordHighlightRule(
        id: 'null_colors',
        label: 'NullColors',
        pattern: 'error',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: null,
      );
      expect(rule.toXtermRule(), isNull);
    });

    test('toXtermRule returns null for invalid regex', () {
      final rule = AppKeywordHighlightRule(
        id: '3',
        label: 'Bad',
        pattern: '[unclosed',
        isRegex: true,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: Colors.red,
      );
      expect(rule.toXtermRule(), isNull);
    });

    test('caseSensitive: false makes pattern case-insensitive', () {
      final rule = AppKeywordHighlightRule(
        id: '4',
        label: 'Error',
        pattern: 'error',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: Colors.red,
      );
      final xterm = rule.toXtermRule();
      expect(xterm!.pattern.hasMatch('ERROR'), isTrue);
      expect(xterm.pattern.hasMatch('Error'), isTrue);
    });

    test('toJson / fromJson roundtrip', () {
      final rule = AppKeywordHighlightRule(
        id: 'abc',
        label: 'Warning',
        pattern: 'warn',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: const Color(0xFF00FF00),
        background: const Color(0xFFFF0000),
      );
      final json = rule.toJson();
      final restored = AppKeywordHighlightRule.fromJson(json);
      expect(restored.id, rule.id);
      expect(restored.label, rule.label);
      expect(restored.pattern, rule.pattern);
      expect(restored.isRegex, rule.isRegex);
      expect(restored.caseSensitive, rule.caseSensitive);
      expect(restored.enabled, rule.enabled);
      expect(restored.foreground?.toARGB32(), rule.foreground?.toARGB32());
      expect(restored.background?.toARGB32(), rule.background?.toARGB32());
    });

    test('kDefaultKeywordHighlightRules all compile without error', () {
      for (final rule in kDefaultKeywordHighlightRules) {
        expect(rule.toXtermRule(), isNotNull,
            reason: '${rule.label} pattern failed to compile');
      }
    });

    test('kDefaultKeywordHighlightRules contains expected labels', () {
      final labels = kDefaultKeywordHighlightRules.map((r) => r.label).toSet();
      expect(labels, containsAll(['Error', 'Warning', 'Success', 'Done', 'OK', 'Debug', 'Info']));
    });
  });
}
