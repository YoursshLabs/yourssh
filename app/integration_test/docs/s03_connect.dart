// 03 first connect: host key prompt, terminal, TUI, search, split, panels, menus, recording.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart' show TerminalView;
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/widgets/theme_picker.dart';
import 'nav.dart';
import 'sections.dart';

const s = '03-first-connect';

SshSession? lastSsh(JourneyContext c) => c.sessions.sshSessions.isEmpty ? null : c.sessions.sshSessions.last;

String termText(SshSession s) => s.terminal.buffer.getText();

Future<void> typeCmd(JourneyContext c, String cmd) async {
  final ssh = c.read<SshService>();
  ssh.sendInput(lastSsh(c)!.id, '$cmd\r');
  await sleepPump(c.t, 900);
}

Future<void> runFirstConnect(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Hosts');
  await c.snap('$s/01-dashboard-before-connect', 'Dashboard with the host card (hover shows actions)');
  await step(c.notes, 'hover', () async {
    await hoverOn(t, find.text('Demo Server'));
    await c.snap('$s/02-card-hover-actions', 'Hovering a host card reveals Test / SFTP / More actions');
  });
  await step(c.notes, 'card menu', () async {
    await tapTooltip(t, 'More', wait: 500);
    await c.snap('$s/03-card-menu', 'Host card "More" menu: Connect, SFTP, Monitor, Edit, Duplicate, Copy URL, Move to group, Export, Delete');
    await pressEscape(t);
  });
  await doubleTap(t, find.text('Demo Server'));
  await sleepPump(t, 1500);
  stdout.writeln('after dblclick sessions=${c.sessions.sessions.length} TEXT=${visibleText().take(40).toList()}');
  if (c.sessions.sessions.isEmpty) {
    c.notes.add('double-click did not open a session in the harness; used connectAny');
  }
  // Host-key dialog (if the app raises one).
  final trust = await waitText(t, 'Trust', seconds: 15, throwOnTimeout: false);
  if (trust) {
    await c.snap('$s/05-host-key-dialog', 'First-use host-key (TOFU) dialog: fingerprint shown, Cancel focused');
    await tapText(t, 'Trust', exact: false, wait: 800);
  } else {
    c.notes.add('No first-use host-key dialog appeared (host accepted silently on first use?). Visible: ${visibleText().take(30).toList()}');
  }
  await waitFor(t, () => lastSsh(c)?.status == SessionStatus.connected, seconds: 30, what: 'ssh connected');
  await sleepPump(t, 2500);
  await c.snap('$s/06-terminal-prompt', 'Terminal connected: shell prompt, header chips/actions, status bar');
  await typeCmd(c, 'ls -la');
  await c.snap('$s/07-terminal-ls', 'Output of `ls -la`');
  await typeCmd(c, 'htop');
  await sleepPump(t, 1500);
  await c.snap('$s/08-terminal-htop', 'A full-screen TUI (htop) running in the terminal');
  c.read<SshService>().sendInput(lastSsh(c)!.id, 'q');
  await sleepPump(t, 800);
  await typeCmd(c, 'clear; for i in 1 2 3; do echo "demo line \$i"; done; hostname');
  await step(c.notes, 'search', () async {
    final tv = find.byType(TerminalView);
    await t.tap(tv.first, warnIfMissed: false);
    await key(t, LogicalKeyboardKey.keyF, meta: true);
    await sleepPump(t, 300);
    final eds = find.byType(EditableText);
    await t.enterText(eds.last, 'demo');
    await sleepPump(t, 500);
    await c.snap('$s/09-terminal-search', 'Terminal search bar (Cmd+F) with matches highlighted');
    await pressEscape(t);
  });
  await step(c.notes, 'input bar', () async {
    await key(t, LogicalKeyboardKey.keyI, ctrl: true, shift: true);
    await sleepPump(t, 500);
    await c.snap('$s/10-input-bar', 'Input bar toggled on (Ctrl+Shift+I)');
    await key(t, LogicalKeyboardKey.keyI, ctrl: true, shift: true);
  });
  await step(c.notes, 'split h', () async {
    await tapTooltip(t, 'Split Horizontal', wait: 1200);
    await c.snap('$s/11-split-horizontal', 'Split horizontal layout');
    await tapTooltip(t, 'Split Vertical', wait: 1200);
    await c.snap('$s/12-split-vertical', 'Split vertical layout');
    await tapTooltip(t, 'Single', wait: 800);
  });
  stdout.writeln('TOOLTIPS terminal: ${tooltips()}');
  await step(c.notes, 'context menu', () async {
    await rightClick(t, find.byType(TerminalView));
    await c.snap('$s/13-terminal-context-menu', 'Right-click context menu in the terminal');
    await pressEscape(t);
  });
  await step(c.notes, 'tab menu', () async {
    await rightClick(t, find.textContaining('Demo Server · demo').first);
    await c.snap('$s/14-tab-context-menu', 'Right-click on the session tab: Rename, Pin, Color tag, Close');
    await tapText(t, 'Color tag', wait: 500);
    await c.snap('$s/15-tab-color-submenu', 'Tab colour submenu');
    await pressEscape(t); // choosing "Color tag" already closed the parent menu; a second Esc would reach the shell
  });
  await step(c.notes, 'tab pin', () async {
    await rightClick(t, find.textContaining('Demo Server · demo').first);
    await tapText(t, 'Pin', wait: 500);
    await c.snap('$s/16-tab-pinned', 'Tab pinned (pin glyph, close button protected)');
    await rightClick(t, find.textContaining('Demo Server · demo').first);
    await tapText(t, 'Unpin', wait: 400);
  });
  await step(c.notes, 'snippets panel', () async {
    await tapTooltip(t, 'Toggle Snippets Panel', wait: 900);
    await c.snap('$s/17-snippets-panel', 'Snippets side panel open beside the terminal');
    await tapTooltip(t, 'Toggle Snippets Panel', wait: 500);
  });
  await step(c.notes, 'terminal settings', () async {
    await tapTooltip(t, 'Toggle Terminal Settings', wait: 900);
    await c.snap('$s/18-terminal-settings-panel', 'Terminal appearance side panel (theme, font size, font)');
    final tp = find.byType(ThemePickerButton);
    if (tp.evaluate().isNotEmpty) {
      await t.tap(tp.first, warnIfMissed: false);
      await sleepPump(t, 700);
      await c.snap('$s/19-theme-picker', 'Terminal theme picker dialog (swatch grid)');
      await pressEscape(t);
    }
    await tapTooltip(t, 'Toggle Terminal Settings', wait: 500);
  });
  await step(c.notes, 'recording', () async {
    await tapTooltip(t, 'Start recording', wait: 900);
    await typeCmd(c, 'echo recorded session; date');
    await c.snap('$s/20-recording-active', 'Recording started: REC indicator active in the header and status bar');
  });
}
