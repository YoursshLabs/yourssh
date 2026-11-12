import 'dart:convert';

import 'package:test/test.dart';
import 'package:yourssh_cli/yourssh_cli.dart';

void main() {
  test('sanitize strips C0, C1, ESC and DEL', () {
    expect(sanitize('a\x1b[31mb\x07\x7f\x85c\n\td'), 'a[31mbcd');
    expect(sanitize(null), '');
  });

  final hosts = <Object?>[
    {
      'label': 'web\x1b]0;pwn\x07',
      'username': 'root',
      'host': 'h\x1b1',
      'port': 22,
      'protocol': 'ssh',
      'tags': ['prod', 'a\x1bb'],
    },
  ];

  test('table has header, sanitized cells and no ANSI without color', () {
    final t = renderHostTable(hosts, color: false);
    expect(t, isNot(contains('\x1b')));
    expect(t.split('\n').first, startsWith('LABEL'));
    expect(t, contains('root@h1:22'));
    expect(t, contains('prod,ab'));
  });

  test('color only bolds the header', () {
    final t = renderHostTable(hosts, color: true);
    expect('\x1b'.allMatches(t).length, 2);
  });

  test('--json escapes DEL and C1 controls that jsonEncode leaves raw', () {
    final label = 'a\x7fb\x80c\x85d\x9fe f\x1bg';
    final out = jsonHosts([
      {'label': label}
    ]);
    for (var c = 0x7f; c <= 0x9f; c++) {
      expect(out.contains(String.fromCharCode(c)), isFalse,
          reason: 'U+${c.toRadixString(16)}');
    }
    expect(out, contains(r'\u007f'));
    expect(out, contains(r'\u0080'));
    expect(out, contains(r'\u0085'));
    expect(out, contains(r'\u009f'));
    expect(out, contains(' ')); // not a control: kept as is
    expect(out, isNot(contains('\x1b'))); // jsonEncode's own escaping
    // Still the same JSON value.
    expect((jsonDecode(out) as List).single, {'label': label});
  });
}
