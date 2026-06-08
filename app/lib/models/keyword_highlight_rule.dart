import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart' as xterm;

class AppKeywordHighlightRule {
  final String id;
  final String label;
  final String pattern;
  final bool isRegex;
  final bool caseSensitive;
  final bool enabled;
  final Color? foreground;
  final Color? background;

  AppKeywordHighlightRule({
    String? id,
    required this.label,
    required this.pattern,
    required this.isRegex,
    required this.caseSensitive,
    required this.enabled,
    required this.foreground,
    required this.background,
  }) : id = id ?? const Uuid().v4();

  xterm.KeywordHighlightRule? toXtermRule() {
    if (foreground == null && background == null) return null;
    try {
      final rawPattern = isRegex ? pattern : RegExp.escape(pattern);
      final compiled = RegExp(rawPattern, caseSensitive: caseSensitive);
      return xterm.KeywordHighlightRule(
        pattern: compiled,
        foreground: foreground,
        background: background,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'pattern': pattern,
        'isRegex': isRegex,
        'caseSensitive': caseSensitive,
        'enabled': enabled,
        'foreground': foreground?.toARGB32(),
        'background': background?.toARGB32(),
      };

  factory AppKeywordHighlightRule.fromJson(Map<String, dynamic> json) {
    return AppKeywordHighlightRule(
      id: json['id'] as String?,
      label: json['label'] as String,
      pattern: json['pattern'] as String,
      isRegex: json['isRegex'] as bool? ?? false,
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      foreground: json['foreground'] != null
          ? Color(json['foreground'] as int)
          : null,
      background: json['background'] != null
          ? Color(json['background'] as int)
          : null,
    );
  }

  AppKeywordHighlightRule copyWith({
    String? label,
    String? pattern,
    bool? isRegex,
    bool? caseSensitive,
    bool? enabled,
    Object? foreground = _unset,
    Object? background = _unset,
  }) {
    return AppKeywordHighlightRule(
      id: id,
      label: label ?? this.label,
      pattern: pattern ?? this.pattern,
      isRegex: isRegex ?? this.isRegex,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      enabled: enabled ?? this.enabled,
      foreground: foreground is _Unset ? this.foreground : foreground as Color?,
      background: background is _Unset ? this.background : background as Color?,
    );
  }
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();

const kMaxKeywordHighlightRules = 20;

final kDefaultKeywordHighlightRules = [
  AppKeywordHighlightRule(
    id: 'default_error',
    label: 'Error',
    pattern: 'error',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: const Color(0xCCB71C1C),
  ),
  AppKeywordHighlightRule(
    id: 'default_fail',
    label: 'Fail',
    pattern: 'fail',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: const Color(0xCCB71C1C),
  ),
  AppKeywordHighlightRule(
    id: 'default_warning',
    label: 'Warning',
    pattern: 'warning',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: const Color(0xCCE65100),
  ),
  AppKeywordHighlightRule(
    id: 'default_warn',
    label: 'Warn',
    pattern: 'warn',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: const Color(0xCCE65100),
  ),
  AppKeywordHighlightRule(
    id: 'default_success',
    label: 'Success',
    pattern: 'success',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: const Color(0xFFA5D6A7),
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_done',
    label: 'Done',
    pattern: 'done',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: const Color(0xFFA5D6A7),
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_ok',
    label: 'OK',
    pattern: r'\bok\b',
    isRegex: true,
    caseSensitive: false,
    enabled: true,
    foreground: const Color(0xFFA5D6A7),
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_debug',
    label: 'Debug',
    pattern: 'debug',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: const Color(0xFF9E9E9E),
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_info',
    label: 'Info',
    pattern: 'info',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: const Color(0xFF80DEEA),
    background: null,
  ),
];
