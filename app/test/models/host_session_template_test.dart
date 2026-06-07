import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

Host _minimal() => Host(label: 'a', host: 'a.com', username: 'u');

Host _full() => Host(
      label: 'a',
      host: 'a.com',
      username: 'u',
      workingDir: '/srv/app',
      envVars: {'FOO': 'bar'},
      startupSnippet: 'htop',
      terminalThemeId: 'Dracula',
      fontFamily: 'MesloLGS NF',
      fontSize: 15,
      termType: 'vt100',
      tmuxOverride: true,
    );

void main() {
  test('defaults: no template, no overrides, hasTemplateSetup false', () {
    final h = _minimal();
    expect(h.workingDir, isNull);
    expect(h.envVars, isEmpty);
    expect(h.startupSnippet, isNull);
    expect(h.terminalThemeId, isNull);
    expect(h.fontFamily, isNull);
    expect(h.fontSize, isNull);
    expect(h.termType, isNull);
    expect(h.tmuxOverride, isNull);
    expect(h.hasTemplateSetup, isFalse);
  });

  test('JSON round-trip preserves all template fields', () {
    final r = Host.fromJson(_full().toJson());
    expect(r.workingDir, '/srv/app');
    expect(r.envVars, {'FOO': 'bar'});
    expect(r.startupSnippet, 'htop');
    expect(r.terminalThemeId, 'Dracula');
    expect(r.fontFamily, 'MesloLGS NF');
    expect(r.fontSize, 15.0);
    expect(r.termType, 'vt100');
    expect(r.tmuxOverride, isTrue);
  });

  test('fromJson tolerates missing fields (old payload)', () {
    final h = Host.fromJson({'host': 'a.com', 'username': 'u'});
    expect(h.envVars, isEmpty);
    expect(h.workingDir, isNull);
    expect(h.tmuxOverride, isNull);
    expect(h.hasTemplateSetup, isFalse);
  });

  test('fromJson tolerates malformed envVars (not a map)', () {
    final h = Host.fromJson(
        {'host': 'a.com', 'username': 'u', 'envVars': 'garbage'});
    expect(h.envVars, isEmpty);
  });

  test('fromJson accepts int fontSize (JSON has no double/int distinction)',
      () {
    final h =
        Host.fromJson({'host': 'a.com', 'username': 'u', 'fontSize': 14});
    expect(h.fontSize, 14.0);
  });

  test('hasTemplateSetup true for each of dir / env / snippet alone', () {
    expect(
        Host(label: 'a', host: 'a.com', username: 'u', workingDir: '/x')
            .hasTemplateSetup,
        isTrue);
    expect(
        Host(label: 'a', host: 'a.com', username: 'u', envVars: {'A': '1'})
            .hasTemplateSetup,
        isTrue);
    expect(
        Host(label: 'a', host: 'a.com', username: 'u', startupSnippet: 'ls')
            .hasTemplateSetup,
        isTrue);
  });

  test('copyWith keeps template fields by default, clears via explicit null',
      () {
    final h = _full();
    final same = h.copyWith(label: 'x');
    expect(same.workingDir, '/srv/app');
    expect(same.envVars, {'FOO': 'bar'});
    expect(same.startupSnippet, 'htop');
    expect(same.terminalThemeId, 'Dracula');
    expect(same.fontFamily, 'MesloLGS NF');
    expect(same.fontSize, 15.0);
    expect(same.termType, 'vt100');
    expect(same.tmuxOverride, isTrue);

    final cleared = h.copyWith(
      workingDir: null,
      startupSnippet: null,
      terminalThemeId: null,
      fontFamily: null,
      fontSize: null,
      termType: null,
      tmuxOverride: null,
    );
    expect(cleared.workingDir, isNull);
    expect(cleared.startupSnippet, isNull);
    expect(cleared.terminalThemeId, isNull);
    expect(cleared.fontFamily, isNull);
    expect(cleared.fontSize, isNull);
    expect(cleared.termType, isNull);
    expect(cleared.tmuxOverride, isNull);
  });

  test('envVars is an owned growable copy', () {
    final h = Host(
        label: 'a', host: 'a.com', username: 'u', envVars: const {'A': '1'});
    expect(() => h.envVars['B'] = '2', returnsNormally);
  });
}
