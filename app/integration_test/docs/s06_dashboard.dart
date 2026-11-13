// 06 dashboard: grid/list, search + facets, select mode, bulk run/diff/push, card menu, delete confirm.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'isolation.dart';
import 'nav.dart';
import 'sections.dart';

const s = '06-dashboard';

Future<void> runDashboard(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Hosts');
  await c.snap('$s/01-grid', 'Hosts dashboard, grid view: groups and host cards, live status dots');
  await step(c.notes, 'list', () async {
    await tapTooltip(t, 'List view', wait: 600);
    await c.snap('$s/02-list', 'List view');
    await tapTooltip(t, 'Grid view', wait: 400);
  });
  await step(c.notes, 'sort', () async {
    await tapText(t, 'Name A→Z', wait: 600);
    await c.snap('$s/03-sort-menu', 'Sort menu');
    await pressEscape(t);
  });
  await step(c.notes, 'search', () async {
    await typeKey(t, 'hosts-search', 'bastion');
    await sleepPump(t, 500);
    await c.snap('$s/04-search', 'Search filters the host list (query "bastion")');
    await typeKey(t, 'hosts-search', '');
    await sleepPump(t, 400);
  });
  await step(c.notes, 'facets', () async {
    await t.tap(find.textContaining(' of ').first, warnIfMissed: false);
    await sleepPump(t, 600);
    await c.snap('$s/04b-filter-facets', 'Clicking the "N of M hosts" counter opens the tag / protocol filter chips');
    await t.tap(find.textContaining(' of ').first, warnIfMissed: false);
    await sleepPump(t, 400);
  });
  await step(c.notes, 'card menu', () async {
    await hoverOn(t, find.text('Bastion').first);
    await tapTooltip(t, 'More', wait: 600);
    await c.snap('$s/05-card-menu', 'Host card menu (Connect, SFTP, Monitor, Edit, Duplicate, Copy URL, Move to group, Export, Delete)');
    await tapText(t, 'Delete', wait: 700);
    await c.snap('$s/06-delete-confirm', 'Delete host confirmation (Cancel focused)');
    await tapText(t, 'Cancel', wait: 500);
  });
  await step(c.notes, 'select mode', () async {
    await tapText(t, 'Select', wait: 600);
    await c.snap('$s/07-select-mode', 'Select mode: checkboxes on cards and the bulk action bar');
    await tapText(t, 'Select all', wait: 500);
    await c.snap('$s/08-select-all', 'All hosts selected; Connect all / Run command / Push files enabled');
    await tapText(t, 'Run command', wait: 800);
    await c.snap('$s/09-bulk-run-empty', 'Bulk Run command dialog (empty)');
    final field = find.byType(EditableText);
    await t.enterText(field.last, 'hostname');
    await sleepPump(t, 300);
    await tapText(t, 'Run', wait: 500);
    await waitFor(t, () => find.textContaining('succeeded').evaluate().isNotEmpty || find.textContaining('done').evaluate().isNotEmpty,
        seconds: 40, throwOnTimeout: false);
    await sleepPump(t, 1500);
    await c.snap('$s/10-bulk-run-results', 'Bulk run finished: per-host status and output');
    await tapText(t, 'Diff', wait: 700);
    await c.snap('$s/11-bulk-run-diff', 'Diff view groups identical outputs and highlights differences');
    await tapText(t, 'Close', wait: 600);
    await tapText(t, 'Push files', wait: 800);
    await c.snap('$s/12-bulk-push', 'Bulk Push files dialog');
    DocsFilePicker.next = ['${Platform.environment['HOME']}/Documents/notes.txt'];
    await tapText(t, 'Add files', wait: 700);
    await step(c.notes, 'dest', () async {
      await t.enterText(find.byType(EditableText).last, '/home/demo/backups');
      await sleepPump(t, 400);
    });
    await c.snap('$s/13-bulk-push-filled', 'Push dialog with a file and destination chosen');
    await tapText(t, 'Close', wait: 600);
    await tapText(t, 'Done', wait: 600);
  });
}
