// Navigation + capture helpers for the docs journey harness.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

/// Records every PNG written so INDEX.md can be generated.
class Shots {
  Shots(this.outDir);
  final String outDir;
  final List<(String path, String caption)> taken = [];

  /// Reads the file written by [snap]; `section/NN-name`.
  Future<void> snap(WidgetTester t, String rel, String caption,
      {int settleMs = 250}) async {
    await t.pump(Duration(milliseconds: settleMs));
    final view = RendererBinding.instance.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    // The root layer already carries the device-pixel-ratio transform, so the
    // rect is in physical pixels and pixelRatio stays 1.
    final image = await layer.toImage(
        Offset.zero & view.flutterView.physicalSize,
        pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$outDir/$rel.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    taken.add(('$rel.png', caption));
    stdout.writeln('SNAP: $rel.png  TEXT: ${visibleText().take(90).toList()}  TIPS: ${tooltips()}');
  }
}

Future<void> setWindow(double w, double h) async {
  // Always on top: an occluded window stops producing frames and hangs pump().
  await windowManager.setAlwaysOnTop(true);
  await windowManager.focus();
  await windowManager.setSize(Size(w, h));
  await windowManager.center();
}

Future<void> sleepPump(WidgetTester t, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> waitFor(WidgetTester t, bool Function() cond,
    {int seconds = 20, String what = 'condition', bool throwOnTimeout = true}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      if (throwOnTimeout) {
        stdout.writeln('TIMEOUT $what; visible: ${visibleText().take(80).toList()}');
        throw TimeoutException('timed out: $what');
      }
      return false;
    }
    await t.pump(const Duration(milliseconds: 150));
  }
  await t.pump(const Duration(milliseconds: 150));
  return true;
}

Future<bool> waitText(WidgetTester t, String text,
        {int seconds = 20, bool throwOnTimeout = true}) =>
    waitFor(t, () => find.textContaining(text).evaluate().isNotEmpty,
        seconds: seconds, what: 'text "$text"', throwOnTimeout: throwOnTimeout);

List<String> visibleText() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText())
    .whereType<String>()
    .toList();

Future<void> tapText(WidgetTester t, String label,
    {bool exact = true, int index = 0, int wait = 400}) async {
  final f = exact ? find.text(label) : find.textContaining(label);
  if (f.evaluate().isEmpty) {
    stdout.writeln('tapText MISSING "$label"; visible: ${visibleText().take(80).toList()}');
    throw StateError('no text "$label"');
  }
  await t.tap(f.at(index.clamp(0, f.evaluate().length - 1)), warnIfMissed: false);
  await t.pump(Duration(milliseconds: wait));
}

Future<void> tapIcon(WidgetTester t, IconData icon, {int index = 0, int wait = 400}) async {
  final f = find.byIcon(icon);
  if (f.evaluate().isEmpty) throw StateError('no icon $icon');
  await t.tap(f.at(index), warnIfMissed: false);
  await t.pump(Duration(milliseconds: wait));
}

Future<void> tapTooltip(WidgetTester t, String message, {int wait = 400}) async {
  final f = find.byTooltip(message);
  if (f.evaluate().isEmpty) throw StateError('no tooltip "$message"');
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(Duration(milliseconds: wait));
}

TestGesture? _mouse;

/// One persistent mouse pointer (adding a second pointer asserts in the tracker).
Future<void> mouseMove(WidgetTester t, Offset to) async {
  if (_mouse == null) {
    _mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await _mouse!.addPointer(location: Offset.zero);
  }
  await _mouse!.moveTo(to);
  await t.pump(const Duration(milliseconds: 350));
}

Future<void> hoverOn(WidgetTester t, Finder f) => mouseMove(t, t.getCenter(f.first));

Future<void> rightClick(WidgetTester t, Finder f) async {
  await t.tap(f.first, buttons: kSecondaryButton, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> pressEscape(WidgetTester t, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump(const Duration(milliseconds: 350));
  }
}

/// Types into the [index]-th editable field (EditableText).
Future<void> typeInto(WidgetTester t, int index, String text) async {
  final f = find.byType(EditableText);
  await t.tap(f.at(index), warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 120));
  await t.enterText(f.at(index), text);
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> typeIntoLabeled(WidgetTester t, String label, String text) async {
  // Find the TextField whose decoration/hint/label contains [label].
  final fields = find.byType(TextField).evaluate().toList();
  for (final e in fields) {
    final w = e.widget as TextField;
    final dec = w.decoration;
    final hay = '${dec?.labelText ?? ''}|${dec?.hintText ?? ''}';
    if (hay.toLowerCase().contains(label.toLowerCase())) {
      final fe = find.byWidget(w);
      await t.tap(fe.first, warnIfMissed: false);
      await t.enterText(fe.first, text);
      await t.pump(const Duration(milliseconds: 200));
      return;
    }
  }
  throw StateError('no field "$label"');
}

Future<void> key(WidgetTester t, LogicalKeyboardKey k,
    {bool meta = false, bool shift = false, bool ctrl = false}) async {
  if (meta) await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(k);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (meta) await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await t.pump(const Duration(milliseconds: 400));
}

Finder byKeyStr(String k) => find.byKey(ValueKey<String>(k));

Future<void> tapKey(WidgetTester t, String k, {int wait = 400}) async {
  final f = byKeyStr(k);
  if (f.evaluate().isEmpty) throw StateError('no key "$k"');
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(Duration(milliseconds: wait));
}

/// Enters [text] into the EditableText inside the widget with ValueKey [k]
/// (or into [k] itself when it is the text field).
Future<void> typeKey(WidgetTester t, String k, String text) async {
  final root = byKeyStr(k);
  if (root.evaluate().isEmpty) throw StateError('no key "$k"');
  var ed = find.descendant(of: root, matching: find.byType(EditableText));
  if (ed.evaluate().isEmpty) ed = root;
  await t.tap(ed.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 100));
  await t.enterText(ed.first, text);
  await t.pump(const Duration(milliseconds: 200));
}

List<String> tooltips() => find
    .byType(Tooltip)
    .evaluate()
    .map((e) => (e.widget as Tooltip).message)
    .whereType<String>()
    .toList();

Future<void> scrollTo(WidgetTester t, Finder f, {double alignment = 0.15}) async {
  if (f.evaluate().isEmpty) throw StateError('scrollTo: not found');
  await Scrollable.ensureVisible(f.first.evaluate().first,
      alignment: alignment, duration: const Duration(milliseconds: 200));
  await t.pump(const Duration(milliseconds: 400));
}

/// Runs an optional step; failures are logged and recorded, never abort.
Future<void> step(List<String> notes, String name, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    stdout.writeln('STEP FAILED [$name]: $e');
    notes.add('Step "$name" failed: $e');
  }
}

Future<void> doubleTap(WidgetTester t, Finder f) async {
  final p = t.getCenter(f.first);
  await t.tapAt(p);
  await t.pump(const Duration(milliseconds: 60));
  await t.tapAt(p);
  await t.pump(const Duration(milliseconds: 400));
}

/// Sidebar navigation: leaves any session tab via the Home tab first.
Future<void> navTo(WidgetTester t, String label, {int wait = 700}) async {
  await pressEscape(t);
  await t.tap(find.text('Home').first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 500));
  if (find.text(label).evaluate().isEmpty) {
    await t.tap(find.text('Home').first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 500));
  }
  await tapText(t, label, index: 0, wait: wait);
}

/// Enters [text] into the EditableText whose current text starts with [current].
Future<void> typeIntoCurrent(WidgetTester t, String current, String text) async {
  final f = find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text.startsWith(current));
  if (f.evaluate().isEmpty) throw StateError('no field starting "$current"');
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 100));
  await t.enterText(f.first, text);
  await t.pump(const Duration(milliseconds: 200));
}
