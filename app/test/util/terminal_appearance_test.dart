import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/terminal_appearance.dart';

void main() {
  TerminalAppearance resolve(Host? host) => resolveTerminalAppearance(
        host: host,
        globalTheme: 'Dracula',
        globalFont: 'MesloLGS NF',
        globalFontSize: 13,
      );

  test('null host → globals', () {
    final a = resolve(null);
    expect(a.themeName, 'Dracula');
    expect(a.fontFamily, 'MesloLGS NF');
    expect(a.fontSize, 13);
  });

  test('host without overrides → globals', () {
    final a = resolve(Host(label: 'h', host: 'h.com', username: 'u'));
    expect(a.themeName, 'Dracula');
    expect(a.fontFamily, 'MesloLGS NF');
    expect(a.fontSize, 13);
  });

  test('host overrides win', () {
    final a = resolve(Host(
        label: 'h',
        host: 'h.com',
        username: 'u',
        terminalThemeId: 'Nord',
        fontFamily: 'monospace',
        fontSize: 16));
    expect(a.themeName, 'Nord');
    expect(a.fontFamily, 'monospace');
    expect(a.fontSize, 16);
  });

  test('unknown host theme falls back to the GLOBAL theme, not catalog[0]',
      () {
    final a = resolve(Host(
        label: 'h', host: 'h.com', username: 'u', terminalThemeId: 'Nope'));
    expect(a.themeName, 'Dracula');
  });

  test('out-of-range host fontSize (e.g. from sync) falls back to global',
      () {
    // The 6–40 validator only runs on local edits; a sync payload bypasses
    // it, and fontSize 0 would zero the line height and break rendering.
    for (final bad in [0.0, -3.0, 500.0]) {
      final a = resolve(
          Host(label: 'h', host: 'h.com', username: 'u', fontSize: bad));
      expect(a.fontSize, 13, reason: 'fontSize $bad must be rejected');
    }
    final ok = resolve(
        Host(label: 'h', host: 'h.com', username: 'u', fontSize: 18));
    expect(ok.fontSize, 18);
  });
}
