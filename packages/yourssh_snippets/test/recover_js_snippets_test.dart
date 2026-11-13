import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

const _native = 'yourssh.snippets';
const _js = 'plugin::dev.yourssh.snippets::storage::snippets';

Map<String, Object> _s(String label, String command, [String id = 'x']) =>
    {'id': id, 'label': label, 'command': command, 'description': '', 'tag': ''};

Future<SharedPreferences> _prefs(Map<String, Object> v) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

List<dynamic> _read(SharedPreferences p, String k) =>
    jsonDecode(p.getString(k)!) as List;

void main() {
  test('missing native key is restored from the JS copy', () async {
    final p = await _prefs({_js: jsonEncode([_s('a', 'ls', 'j1')])});
    await recoverJsSnippets(p);
    expect(_read(p, _native).single['label'], 'a');
    expect(p.getString(_js), isNotNull, reason: 'JS copy is never deleted');
  });

  test('both present: JS-only entries are appended, no duplicates', () async {
    final p = await _prefs({
      _native: jsonEncode([_s('a', 'ls', 'n1')]),
      _js: jsonEncode([_s('a', 'ls', 'j1'), _s('b', 'pwd', 'j2')]),
    });
    await recoverJsSnippets(p);
    expect(_read(p, _native).map((e) => e['label']), ['a', 'b']);
    await recoverJsSnippets(p);
    expect(_read(p, _native), hasLength(2));
  });

  test('a snippet deleted later is not resurrected on the next launch', () async {
    final p = await _prefs({_js: jsonEncode([_s('a', 'ls', 'j1')])});
    await recoverJsSnippets(p);
    await p.setString(_native, jsonEncode([]));
    await recoverJsSnippets(p);
    expect(_read(p, _native), isEmpty);
  });

  test('malformed JS JSON leaves everything untouched', () async {
    final p = await _prefs({_js: '{not json'});
    await recoverJsSnippets(p);
    expect(p.getString(_native), isNull);
    final q = await _prefs({_native: jsonEncode([_s('a', 'ls')]), _js: '"str"'});
    await recoverJsSnippets(q);
    expect(_read(q, _native), hasLength(1));
  });

  test('nothing stored: untouched; empty JS array: untouched', () async {
    final p = await _prefs({});
    await recoverJsSnippets(p);
    expect(p.getString(_native), isNull);
    final q = await _prefs({_js: '[]'});
    await recoverJsSnippets(q);
    expect(q.getString(_native), isNull);
  });
}
