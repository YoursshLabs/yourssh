import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/plugin_manifest.dart';

void main() {
  const validJson = '''
  {
    "id": "dev.yourssh.test",
    "name": "Test Plugin",
    "version": "1.0.0",
    "entry": "index.js",
    "minAppVersion": "1.0.0",
    "permissions": ["terminal.transform", "session.observe"]
  }
  ''';

  test('parses valid manifest', () {
    final m = PluginManifest.fromJson(validJson);
    expect(m.id, 'dev.yourssh.test');
    expect(m.name, 'Test Plugin');
    expect(m.version, '1.0.0');
    expect(m.entry, 'index.js');
    expect(m.permissions, contains('terminal.transform'));
    expect(m.permissions, contains('session.observe'));
  });

  test('rejects invalid id (spaces)', () {
    final bad = validJson.replaceFirst('"dev.yourssh.test"', '"bad id"');
    expect(() => PluginManifest.fromJson(bad), throwsA(isA<ManifestException>()));
  });

  test('rejects unknown permissions', () {
    final bad = validJson.replaceFirst('"terminal.transform"', '"unknown.perm"');
    expect(() => PluginManifest.fromJson(bad), throwsA(isA<ManifestException>()));
  });

  test('rejects missing required field: name', () {
    expect(() => PluginManifest.fromJson('{"id":"dev.x","version":"1.0.0","entry":"index.js","minAppVersion":"1.0.0","permissions":[]}'),
        throwsA(isA<ManifestException>()));
  });

  test('rejects invalid JSON', () {
    expect(() => PluginManifest.fromJson('not json'),
        throwsA(isA<ManifestException>()));
  });

  test('accepts empty permissions list', () {
    final json = validJson.replaceFirst(
        '"terminal.transform", "session.observe"', '');
    final m = PluginManifest.fromJson(json);
    expect(m.permissions, isEmpty);
  });
}
