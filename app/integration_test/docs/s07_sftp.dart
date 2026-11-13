// 07 SFTP dual panel: browse, select vs open, context menu, upload, permissions, rename, mkdir, delete, editor, executable confirm.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '07-sftp';

Future<void> runSftp(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'SFTP', wait: 900);
  await c.snap('$s/01-sftp-not-connected', 'SFTP screen before choosing a host: local panel + "Connect to host" prompt');
  await step(c.notes, 'select host', () async {
    await tapText(t, 'Select host', wait: 800);
    await c.snap('$s/02-host-picker', 'Host picker for the remote panel');
    await tapText(t, 'Demo Server', index: 0, wait: 1200);
    await waitFor(t, () => find.text('bin').evaluate().isNotEmpty, seconds: 30, throwOnTimeout: false);
    await sleepPump(t, 800);
    await c.snap('$s/03-dual-panel', 'Dual-panel SFTP: local demo home on the left, /home/demo on the right');
  });
  await step(c.notes, 'local docs', () async {
    await doubleTap(t, find.text('Documents').first);
    await sleepPump(t, 900);
    await c.snap('$s/04-local-documents', 'Local panel navigated into Documents');
  });
  await step(c.notes, 'remote navigate', () async {
    await doubleTap(t, find.text('home').first);
    await sleepPump(t, 900);
    await doubleTap(t, find.text('demo').first);
    await sleepPump(t, 900);
    await c.snap('$s/04b-remote-home', 'Remote panel inside /home/demo');
    await doubleTap(t, find.text('projects').first);
    await sleepPump(t, 1200);
    await c.snap('$s/05-remote-projects', 'Remote panel navigated into projects');
    await t.tap(find.text('webapp').first, warnIfMissed: false);
    await sleepPump(t, 400);
    await c.snap('$s/06-select-single-click', 'Single click selects an entry (does not open it)');
  });
  await step(c.notes, 'context menu', () async {
    await mouseMove(t, const Offset(1000, 700));
    await rightClick(t, find.text('webapp').first);
    await c.snap('$s/07-remote-context-menu', 'Remote entry context menu (Open, Copy to target directory, Rename, Delete, Refresh, New Folder, Edit Permissions, Copy path)');
    await pressEscape(t);
  });
  await step(c.notes, 'local ctx', () async {
    await mouseMove(t, const Offset(1000, 700));
    await rightClick(t, find.text('notes.txt').first);
    await c.snap('$s/08-local-context-menu', 'Local file context menu');
    await pressEscape(t);
  });
  await step(c.notes, 'enter webapp', () async {
    await doubleTap(t, find.text('webapp').first);
    await sleepPump(t, 1200);
    await c.snap('$s/09-remote-webapp', 'Remote panel inside projects/webapp');
  });
  await step(c.notes, 'upload', () async {
    await rightClick(t, find.text('notes.txt').first);
    await tapText(t, 'Copy to target directory', wait: 300);
    await c.snap('$s/10-upload-progress', 'Upload started: the transfer queue appears at the bottom', settleMs: 120);
    await sleepPump(t, 2500);
    await c.snap('$s/11-upload-done', 'Transfer finished: the file is listed in the remote panel');
  });
  await step(c.notes, 'permissions', () async {
    await rightClick(t, find.text('notes.txt').last);
    await tapText(t, 'Edit Permissions', wait: 900);
    await c.snap('$s/12-permissions-dialog', 'Permissions dialog: rwx grid, octal mode, Apply recursively');
    await tapText(t, 'Cancel', wait: 500);
  });
  await step(c.notes, 'rename', () async {
    await rightClick(t, find.text('notes.txt').last);
    await tapText(t, 'Rename', wait: 800);
    await c.snap('$s/13-rename-dialog', 'Rename dialog');
    await tapText(t, 'Cancel', wait: 500);
  });
  await step(c.notes, 'new folder', () async {
    await rightClick(t, find.text('notes.txt').last);
    await tapText(t, 'New Folder', wait: 800);
    await t.enterText(find.byType(EditableText).last, 'releases');
    await sleepPump(t, 300);
    await c.snap('$s/14-new-folder-dialog', 'New Folder dialog with a name entered');
    await tapText(t, 'Create', wait: 1200);
    await c.snap('$s/15-folder-created', 'The new folder appears in the listing');
  });
  await step(c.notes, 'mkdir existing', () async {
    await rightClick(t, find.text('notes.txt').last);
    await tapText(t, 'New Folder', wait: 800);
    await t.enterText(find.byType(EditableText).last, 'releases');
    await sleepPump(t, 300);
    await tapText(t, 'Create', wait: 700);
    await c.snap('$s/15b-mkdir-existing', 'Creating a folder whose name already exists: the error message shown to the user');
    if (find.text('Cancel').evaluate().isNotEmpty) await tapText(t, 'Cancel', wait: 500);
  });
  await step(c.notes, 'delete', () async {
    await rightClick(t, find.text('releases').last);
    await tapText(t, 'Delete', wait: 800);
    await c.snap('$s/16-delete-confirm', 'Delete confirmation (names the entry, "cannot be undone")');
    await tapText(t, 'Cancel', wait: 500);
  });
  await step(c.notes, 'editor', () async {
    final readme = find.text('README.md');
    if (readme.evaluate().length < 2) throw StateError('remote README.md not found');
    await doubleTap(t, readme.last);
    await sleepPump(t, 4000);
    await c.snap('$s/17-code-editor', 'Double-click a text file opens the in-app code editor (toolbar: back, save). The Monaco web view itself is a native view and is not captured by the render-tree harness, so the editor body is blank here');
    await pressEscape(t);
    if (find.byTooltip('Close').evaluate().isNotEmpty) await tapTooltip(t, 'Close', wait: 800);
    else if (find.byTooltip('Back').evaluate().isNotEmpty) await tapTooltip(t, 'Back', wait: 800);
  });
  await step(c.notes, 'open externally', () async {
    await doubleTap(t, find.text('run-demo.command').first);
    await sleepPump(t, 800);
    await c.snap('$s/18-run-file-confirm', '"Run this file?" confirmation for an executable in the local panel');
    await tapText(t, 'Cancel', wait: 500);
  });
  await pressEscape(t, times: 2);
}
