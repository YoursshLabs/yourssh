# Keyword Highlighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-defined regex/literal rules that tint matching text in terminal output with configurable foreground and/or background colors, with verbose defaults and global settings UI.

**Architecture:** Render-layer overlay in the xterm fork — `RenderTerminal` scans only visible lines at paint time using `BufferLine.getText()` + regex, then draws colored rects (background) and re-renders text cells (foreground) on top of normal ANSI output. No data mutation, recordings unaffected.

**Tech Stack:** Dart/Flutter, xterm fork (`packages/xterm`), `shared_preferences`, `uuid`, `provider`.

---

## File Map

| File | Action |
|------|--------|
| `packages/xterm/lib/src/ui/keyword_highlight.dart` | Create — xterm-layer rule type |
| `packages/xterm/lib/ui.dart` | Modify — add export |
| `packages/xterm/lib/src/ui/painter.dart` | Modify — add `paintKeywordForeground()` |
| `packages/xterm/lib/src/ui/render.dart` | Modify — add `_keywordRules` + `_paintKeywordHighlights()` |
| `packages/xterm/lib/src/terminal_view.dart` | Modify — thread `keywordRules` param |
| `app/lib/models/keyword_highlight_rule.dart` | Create — app-layer model + defaults |
| `app/test/models/keyword_highlight_rule_test.dart` | Create — unit tests |
| `app/lib/providers/settings_provider.dart` | Modify — add 2 fields + persist |
| `app/test/settings_provider_test.dart` | Modify — add persistence tests |
| `app/lib/widgets/terminal_view.dart` | Modify — wire compiled rules to TerminalView |
| `app/lib/widgets/keyword_highlight_settings.dart` | Create — settings UI (rule list + add/edit dialog) |
| `app/lib/widgets/settings_screen.dart` | Modify — add keyword highlighting section |
| `app/lib/widgets/terminal_config_panel.dart` | Modify — add compact toggle section |

---

### Task 1: xterm KeywordHighlightRule type

**Files:**
- Create: `packages/xterm/lib/src/ui/keyword_highlight.dart`
- Modify: `packages/xterm/lib/ui.dart`

- [ ] **Step 1: Create the xterm-layer rule type**

```dart
// packages/xterm/lib/src/ui/keyword_highlight.dart
import 'dart:ui';

class KeywordHighlightRule {
  final RegExp pattern;
  final Color? foreground;
  final Color? background;

  const KeywordHighlightRule({
    required this.pattern,
    this.foreground,
    this.background,
  });
}
```

- [ ] **Step 2: Export from `packages/xterm/lib/ui.dart`**

Add this line to `packages/xterm/lib/ui.dart`:

```dart
export 'src/ui/keyword_highlight.dart';
```

The final file should be:

```dart
export 'src/terminal_view.dart';
export 'src/ui/clipboard_ops.dart';
export 'src/ui/controller.dart';
export 'src/ui/cursor_type.dart';
export 'src/ui/keyboard_highlight.dart';
export 'src/ui/keyboard_visibility.dart';
export 'src/ui/pointer_input.dart';
export 'src/ui/selection_mode.dart';
export 'src/ui/shortcut/shortcuts.dart';
export 'src/ui/terminal_text_style.dart';
export 'src/ui/terminal_theme.dart';
export 'src/ui/themes.dart';
```

- [ ] **Step 3: Verify the package compiles**

```bash
cd packages/xterm && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add packages/xterm/lib/src/ui/keyword_highlight.dart packages/xterm/lib/ui.dart
git commit -m "feat(xterm): KeywordHighlightRule type for render-layer keyword highlighting"
```

---

### Task 2: painter.paintKeywordForeground()

**Files:**
- Modify: `packages/xterm/lib/src/ui/painter.dart`

Add `paintKeywordForeground()` after the `paintHighlight()` method (around line 138). This method re-renders specific cells with an override foreground color, bypassing the paragraph cache (which is keyed to the original ANSI color).

- [ ] **Step 1: Add `paintKeywordForeground()` to `TerminalPainter`**

Insert after `paintHighlight()`:

```dart
/// Re-renders cells in [startCol]..[endCol] on [line] with [fgColor],
/// bypassing the paragraph cache. Uses the same coordinate system as
/// [paintHighlight]: [lineOffset] is Offset(0, lineY) without canvas offset.
void paintKeywordForeground(
  Canvas canvas,
  Offset lineOffset,
  BufferLine line,
  int startCol,
  int endCol,
  Color fgColor,
) {
  final cellData = CellData.empty();
  final cellWidth = _cellSize.width;

  for (var i = startCol; i < endCol && i < line.length; i++) {
    line.getCellData(i, cellData);
    final charCode = cellData.content & CellContent.codepointMask;
    final charWidth = cellData.content >> CellContent.widthShift;

    if (charCode != 0) {
      final style = _textStyle.toTextStyle(color: fgColor);
      final builder = ParagraphBuilder(style.getParagraphStyle())
        ..pushStyle(style.getTextStyle(textScaler: _textScaler))
        ..addText(String.fromCharCode(charCode));
      final para = builder.build()
        ..layout(ParagraphConstraints(width: cellWidth * 2));
      canvas.drawParagraph(para, lineOffset.translate(i * cellWidth, 0));
      para.dispose();
    }

    if (charWidth == 2) i++; // skip phantom cell of double-width char
  }
}
```

- [ ] **Step 2: Verify the package compiles**

```bash
cd packages/xterm && flutter analyze
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add packages/xterm/lib/src/ui/painter.dart
git commit -m "feat(xterm): paintKeywordForeground — re-render cells with override color"
```

---

### Task 3: RenderTerminal keyword rules + _paintKeywordHighlights()

**Files:**
- Modify: `packages/xterm/lib/src/ui/render.dart`

- [ ] **Step 1: Add import for `keyword_highlight.dart`**

In `packages/xterm/lib/src/ui/render.dart`, add this import after the existing ui imports:

```dart
import 'package:xterm/src/ui/keyword_highlight.dart';
```

- [ ] **Step 2: Add `_keywordRules` property to `RenderTerminal`**

Add after `final TerminalPainter _painter;` (around line 152):

```dart
List<KeywordHighlightRule> _keywordRules = const [];
set keywordRules(List<KeywordHighlightRule> value) {
  if (_keywordRules == value) return;
  _keywordRules = value;
  markNeedsPaint();
}
```

- [ ] **Step 3: Add `_paintKeywordHighlights()` method**

Add after `_paintSelection()` (before or after `_paintSegment()`, at the end of the class):

```dart
void _paintKeywordHighlights(Canvas canvas, int firstLine, int lastLine) {
  if (_keywordRules.isEmpty) return;
  final lines = _terminal.buffer.lines;
  final charHeight = _painter.cellSize.height;

  for (var i = firstLine; i <= lastLine; i++) {
    if (i >= lines.length) break;
    final lineText = lines[i].getText();
    final lineY = i * charHeight + _lineOffset;

    for (final rule in _keywordRules) {
      for (final m in rule.pattern.allMatches(lineText)) {
        if (m.start == m.end) continue;

        if (rule.background != null) {
          _painter.paintHighlight(
            canvas,
            Offset(m.start * _painter.cellSize.width, lineY),
            m.end - m.start,
            rule.background!,
          );
        }

        if (rule.foreground != null) {
          _painter.paintKeywordForeground(
            canvas,
            Offset(0, lineY),
            lines[i],
            m.start,
            m.end,
            rule.foreground!,
          );
        }
      }
    }
  }
}
```

- [ ] **Step 4: Call `_paintKeywordHighlights()` in `_paint()`**

In `_paint()`, after the for-loop that paints lines and before the cursor block, insert:

```dart
_paintKeywordHighlights(canvas, effectFirstLine, effectLastLine);
```

The full `_paint()` structure becomes:

```dart
// 1. paint lines
for (var i = effectFirstLine; i <= effectLastLine; i++) {
  _painter.paintLine(...);
}

// 2. keyword highlights (NEW — before cursor so cursor stays on top)
_paintKeywordHighlights(canvas, effectFirstLine, effectLastLine);

// 3. cursor
if (_terminal.buffer.absoluteCursorY >= effectFirstLine && ...) { ... }

// 4. search highlights (on top of keyword highlights)
_paintHighlights(canvas, _controller.highlights, effectFirstLine, effectLastLine);

// 5. selection
if (_controller.selection != null) { ... }
```

- [ ] **Step 5: Verify the package compiles**

```bash
cd packages/xterm && flutter analyze
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add packages/xterm/lib/src/ui/render.dart
git commit -m "feat(xterm): render keyword highlights on visible lines at paint time"
```

---

### Task 4: Thread keywordRules through xterm TerminalView

**Files:**
- Modify: `packages/xterm/lib/src/terminal_view.dart`

- [ ] **Step 1: Add `keywordRules` field to `TerminalView`**

In the `TerminalView` class, add after `simulateScroll`:

```dart
/// Rules for keyword highlighting. Applied at paint time — only visible
/// lines are scanned. Defaults to an empty list (no highlighting).
final List<KeywordHighlightRule> keywordRules;
```

Add `this.keywordRules = const [],` to the constructor parameter list (after `simulateScroll`).

- [ ] **Step 2: Add `keywordRules` to `_TerminalView`**

In `_TerminalView`:

Add field:
```dart
final List<KeywordHighlightRule> keywordRules;
```

Add to constructor `const _TerminalView({...})`:
```dart
required this.keywordRules,
```

- [ ] **Step 3: Wire into `createRenderObject` and `updateRenderObject`**

In `_TerminalView.createRenderObject()`:
```dart
return RenderTerminal(
  // ... existing params ...
  keywordRules: keywordRules,   // ADD THIS
);
```

Wait — `RenderTerminal`'s constructor doesn't have `keywordRules` yet (it's set via the setter). After creating the object, set it:

```dart
@override
RenderTerminal createRenderObject(BuildContext context) {
  final renderObject = RenderTerminal(
    terminal: terminal,
    controller: controller,
    offset: offset,
    padding: padding,
    autoResize: autoResize,
    textStyle: textStyle,
    textScaler: textScaler,
    theme: theme,
    focusNode: focusNode,
    cursorType: cursorType,
    alwaysShowCursor: alwaysShowCursor,
    onEditableRect: onEditableRect,
    composingText: composingText,
  );
  renderObject.keywordRules = keywordRules;
  return renderObject;
}
```

In `_TerminalView.updateRenderObject()`:
```dart
@override
void updateRenderObject(BuildContext context, RenderTerminal renderObject) {
  renderObject
    ..terminal = terminal
    ..controller = controller
    ..offset = offset
    ..padding = padding
    ..autoResize = autoResize
    ..textStyle = textStyle
    ..textScaler = textScaler
    ..theme = theme
    ..focusNode = focusNode
    ..cursorType = cursorType
    ..alwaysShowCursor = alwaysShowCursor
    ..onEditableRect = onEditableRect
    ..composingText = composingText
    ..keywordRules = keywordRules;   // ADD THIS
}
```

- [ ] **Step 4: Thread from `TerminalViewState.build()` to `_TerminalView`**

In `TerminalViewState.build()`, find where `_TerminalView` is constructed and add `keywordRules: widget.keywordRules`.

- [ ] **Step 5: Add import for `keyword_highlight.dart` at the top of `terminal_view.dart`**

```dart
import 'package:xterm/src/ui/keyword_highlight.dart';
```

- [ ] **Step 6: Verify the package compiles**

```bash
cd packages/xterm && flutter analyze
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add packages/xterm/lib/src/terminal_view.dart
git commit -m "feat(xterm): thread keywordRules through TerminalView → RenderTerminal"
```

---

### Task 5: AppKeywordHighlightRule model + tests

**Files:**
- Create: `app/lib/models/keyword_highlight_rule.dart`
- Create: `app/test/models/keyword_highlight_rule_test.dart`

- [ ] **Step 1: Write failing tests first**

Create `app/test/models/keyword_highlight_rule_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/keyword_highlight_rule.dart';

void main() {
  group('AppKeywordHighlightRule', () {
    test('toXtermRule compiles literal pattern with escape', () {
      final rule = AppKeywordHighlightRule(
        id: '1',
        label: 'Error',
        pattern: 'error[test]',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: Colors.red,
      );
      final xterm = rule.toXtermRule();
      expect(xterm, isNotNull);
      // Literal match: "error[test]" as a string, not a char class
      expect(xterm!.pattern.hasMatch('error[test]'), isTrue);
      expect(xterm.pattern.hasMatch('errort'), isFalse);
    });

    test('toXtermRule compiles regex pattern', () {
      final rule = AppKeywordHighlightRule(
        id: '2',
        label: 'OK',
        pattern: r'\bok\b',
        isRegex: true,
        caseSensitive: false,
        enabled: true,
        foreground: Colors.green,
        background: null,
      );
      final xterm = rule.toXtermRule();
      expect(xterm, isNotNull);
      expect(xterm!.pattern.hasMatch('ok'), isTrue);
      expect(xterm.pattern.hasMatch('working'), isFalse);
    });

    test('toXtermRule returns null for invalid regex', () {
      final rule = AppKeywordHighlightRule(
        id: '3',
        label: 'Bad',
        pattern: '[unclosed',
        isRegex: true,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: Colors.red,
      );
      expect(rule.toXtermRule(), isNull);
    });

    test('caseSensitive: false makes pattern case-insensitive', () {
      final rule = AppKeywordHighlightRule(
        id: '4',
        label: 'Error',
        pattern: 'error',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: Colors.red,
      );
      final xterm = rule.toXtermRule();
      expect(xterm!.pattern.hasMatch('ERROR'), isTrue);
      expect(xterm.pattern.hasMatch('Error'), isTrue);
    });

    test('toJson / fromJson roundtrip', () {
      final rule = AppKeywordHighlightRule(
        id: 'abc',
        label: 'Warning',
        pattern: 'warn',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: const Color(0xFF00FF00),
        background: const Color(0xFFFF0000),
      );
      final json = rule.toJson();
      final restored = AppKeywordHighlightRule.fromJson(json);
      expect(restored.id, rule.id);
      expect(restored.label, rule.label);
      expect(restored.pattern, rule.pattern);
      expect(restored.isRegex, rule.isRegex);
      expect(restored.caseSensitive, rule.caseSensitive);
      expect(restored.enabled, rule.enabled);
      expect(restored.foreground?.value, rule.foreground?.value);
      expect(restored.background?.value, rule.background?.value);
    });

    test('kDefaultKeywordHighlightRules all compile without error', () {
      for (final rule in kDefaultKeywordHighlightRules) {
        expect(rule.toXtermRule(), isNotNull,
            reason: '${rule.label} pattern failed to compile');
      }
    });

    test('kDefaultKeywordHighlightRules contains expected labels', () {
      final labels = kDefaultKeywordHighlightRules.map((r) => r.label).toSet();
      expect(labels, containsAll(['Error', 'Warning', 'Success', 'Done', 'OK', 'Debug', 'Info']));
    });
  });
}
```

- [ ] **Step 2: Run failing tests**

```bash
cd app && flutter test test/models/keyword_highlight_rule_test.dart
```

Expected: FAIL — `keyword_highlight_rule.dart` doesn't exist yet.

- [ ] **Step 3: Create the model**

Create `app/lib/models/keyword_highlight_rule.dart`:

```dart
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

  /// Compiles this rule into an xterm render-layer rule.
  /// Returns null if the regex pattern is invalid — callers should skip null results.
  xterm.KeywordHighlightRule? toXtermRule() {
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
        'foreground': foreground?.value,
        'background': background?.value,
      };

  factory AppKeywordHighlightRule.fromJson(Map<String, dynamic> json) {
    return AppKeywordHighlightRule(
      id: json['id'] as String,
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
    background: Color(0xFFB71C1C), // Colors.red.shade900
  ),
  AppKeywordHighlightRule(
    id: 'default_fail',
    label: 'Fail',
    pattern: 'fail',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: Color(0xFFB71C1C),
  ),
  AppKeywordHighlightRule(
    id: 'default_warning',
    label: 'Warning',
    pattern: 'warning',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: Color(0xFFE65100), // Colors.deepOrange.shade900
  ),
  AppKeywordHighlightRule(
    id: 'default_warn',
    label: 'Warn',
    pattern: 'warn',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: null,
    background: Color(0xFFE65100),
  ),
  AppKeywordHighlightRule(
    id: 'default_success',
    label: 'Success',
    pattern: 'success',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: Color(0xFFA5D6A7), // Colors.green.shade200
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_done',
    label: 'Done',
    pattern: 'done',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: Color(0xFFA5D6A7),
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_ok',
    label: 'OK',
    pattern: r'\bok\b',
    isRegex: true,
    caseSensitive: false,
    enabled: true,
    foreground: Color(0xFFA5D6A7),
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_debug',
    label: 'Debug',
    pattern: 'debug',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: Color(0xFF9E9E9E), // Colors.grey.shade500
    background: null,
  ),
  AppKeywordHighlightRule(
    id: 'default_info',
    label: 'Info',
    pattern: 'info',
    isRegex: false,
    caseSensitive: false,
    enabled: true,
    foreground: Color(0xFF80DEEA), // Colors.cyan.shade200
    background: null,
  ),
];
```

- [ ] **Step 4: Run tests and verify they pass**

```bash
cd app && flutter test test/models/keyword_highlight_rule_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/keyword_highlight_rule.dart app/test/models/keyword_highlight_rule_test.dart
git commit -m "feat: AppKeywordHighlightRule model with toXtermRule, JSON roundtrip, and verbose defaults"
```

---

### Task 6: SettingsProvider + tests

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Modify: `app/test/settings_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Add to `app/test/settings_provider_test.dart`:

```dart
import 'dart:convert';
// (existing imports remain)
import 'package:yourssh/models/keyword_highlight_rule.dart';

// inside main():

  group('keyword highlighting', () {
    test('keywordHighlightingEnabled defaults to true', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(provider.keywordHighlightingEnabled, isTrue);
    });

    test('keywordHighlightRules defaults to kDefaultKeywordHighlightRules', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(provider.keywordHighlightRules.length,
          kDefaultKeywordHighlightRules.length);
    });

    test('save persists keywordHighlightingEnabled', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      await provider.save(keywordHighlightingEnabled: false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('keywordHighlightingEnabled'), isFalse);
    });

    test('save persists keywordHighlightRules as JSON', () async {
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      final rule = AppKeywordHighlightRule(
        id: 'x',
        label: 'Test',
        pattern: 'test',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: const Color(0xFFFF0000),
      );
      await provider.save(keywordHighlightRules: [rule]);
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('keywordHighlightRules');
      expect(json, isNotNull);
      final decoded = jsonDecode(json!) as List;
      expect(decoded.length, 1);
      expect(decoded[0]['id'], 'x');
    });

    test('loads persisted keywordHighlightRules on init', () async {
      final rule = AppKeywordHighlightRule(
        id: 'y',
        label: 'Loaded',
        pattern: 'loaded',
        isRegex: false,
        caseSensitive: false,
        enabled: true,
        foreground: null,
        background: null,
      );
      SharedPreferences.setMockInitialValues({
        'keywordHighlightRules': jsonEncode([rule.toJson()]),
        'keywordHighlightingEnabled': false,
      });
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);
      expect(provider.keywordHighlightRules.length, 1);
      expect(provider.keywordHighlightRules[0].id, 'y');
      expect(provider.keywordHighlightingEnabled, isFalse);
    });
  });
```

- [ ] **Step 2: Run failing tests**

```bash
cd app && flutter test test/settings_provider_test.dart
```

Expected: FAIL — fields don't exist yet.

- [ ] **Step 3: Add fields to `SettingsProvider`**

At the top of the fields section in `settings_provider.dart`, add:

```dart
bool keywordHighlightingEnabled = true;
List<AppKeywordHighlightRule> keywordHighlightRules = kDefaultKeywordHighlightRules;
```

Add import at top of file:
```dart
import 'package:yourssh/models/keyword_highlight_rule.dart';
```

- [ ] **Step 4: Load in `_load()`**

Inside `_load()`, after the other `prefs.get*` calls:

```dart
keywordHighlightingEnabled =
    prefs.getBool('keywordHighlightingEnabled') ?? true;
final rulesJson = prefs.getString('keywordHighlightRules');
if (rulesJson != null) {
  try {
    keywordHighlightRules = (jsonDecode(rulesJson) as List<dynamic>)
        .map((j) => AppKeywordHighlightRule.fromJson(j as Map<String, dynamic>))
        .toList();
  } catch (_) {
    keywordHighlightRules = kDefaultKeywordHighlightRules;
  }
}
```

- [ ] **Step 5: Persist in `save()`**

Add to the `save()` method signature:
```dart
bool? keywordHighlightingEnabled,
List<AppKeywordHighlightRule>? keywordHighlightRules,
```

Add to the assignment block:
```dart
if (keywordHighlightingEnabled != null) this.keywordHighlightingEnabled = keywordHighlightingEnabled;
if (keywordHighlightRules != null) this.keywordHighlightRules = keywordHighlightRules;
```

Add to the `prefs.set*` block:
```dart
await prefs.setBool('keywordHighlightingEnabled', this.keywordHighlightingEnabled);
await prefs.setString('keywordHighlightRules', jsonEncode(this.keywordHighlightRules.map((r) => r.toJson()).toList()));
```

- [ ] **Step 6: Run tests and verify they pass**

```bash
cd app && flutter test test/settings_provider_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/settings_provider_test.dart
git commit -m "feat: SettingsProvider — keywordHighlightingEnabled + keywordHighlightRules persistence"
```

---

### Task 7: Wire compiled rules into app terminal_view.dart

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart`

- [ ] **Step 1: Add `context.select` for keyword rules in `_TerminalWidgetState.build()`**

In `_TerminalWidgetState.build()`, before the `return Stack(...)`, add:

```dart
final keywordRules = context.select<SettingsProvider, List<KeywordHighlightRule>>(
  (s) => s.keywordHighlightingEnabled
      ? s.keywordHighlightRules
          .where((r) => r.enabled)
          .map((r) => r.toXtermRule())
          .whereType<KeywordHighlightRule>()
          .toList()
      : const [],
);
```

(`KeywordHighlightRule` here is `xterm.KeywordHighlightRule` — already imported via `package:xterm/xterm.dart`.)

- [ ] **Step 2: Pass `keywordRules` to `TerminalView`**

In the `TerminalView(...)` constructor call (around line 440), add:

```dart
keywordRules: keywordRules,
```

- [ ] **Step 3: Verify the app compiles**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Smoke test — run the app and verify highlighting appears**

```bash
cd app && flutter run -d macos
```

Open a terminal session. Type `echo error` — the word "error" should appear with a dark red background. Type `echo success` — "success" should appear in green text. If both work, the render layer is wired correctly.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/terminal_view.dart
git commit -m "feat: wire keyword highlight rules from SettingsProvider into TerminalView"
```

---

### Task 8: Settings screen UI — keyword highlighting section

**Files:**
- Create: `app/lib/widgets/keyword_highlight_settings.dart`
- Modify: `app/lib/widgets/settings_screen.dart`

- [ ] **Step 1: Create `app/lib/widgets/keyword_highlight_settings.dart`**

This file contains:
- `KeywordHighlightSection` — the full settings section (rule list + add button + master toggle)
- `_RuleRow` — individual rule row widget
- `_KeywordRuleDialog` — add/edit dialog
- `_ColorPickerButton` — nullable color selector
- `_kPresetColors` — list of preset colors

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/keyword_highlight_rule.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

// Preset colors suitable for terminal highlighting
const _kForegroundPresets = [
  Color(0xFFEF9A9A), // red.shade200
  Color(0xFFFFCC80), // orange.shade200
  Color(0xFFFFF176), // yellow.shade300
  Color(0xFFA5D6A7), // green.shade200
  Color(0xFF80DEEA), // cyan.shade200
  Color(0xFF90CAF9), // blue.shade200
  Color(0xFFCE93D8), // purple.shade200
  Color(0xFFFFFFFF), // white
  Color(0xFF9E9E9E), // grey.shade500
  Color(0xFFBDBDBD), // grey.shade400
];

const _kBackgroundPresets = [
  Color(0xFFB71C1C), // red.shade900
  Color(0xFFE65100), // deepOrange.shade900
  Color(0xFFF57F17), // amber.shade900
  Color(0xFF1B5E20), // green.shade900
  Color(0xFF006064), // cyan.shade900
  Color(0xFF0D47A1), // blue.shade900
  Color(0xFF4A148C), // purple.shade900
  Color(0xFF37474F), // blueGrey.shade800
];

class KeywordHighlightSection extends StatelessWidget {
  const KeywordHighlightSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Master toggle
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('Enable keyword highlighting',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text(
              'Tint matching text in all terminal sessions',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: settings.keywordHighlightingEnabled,
          onChanged: (v) => context
              .read<SettingsProvider>()
              .save(keywordHighlightingEnabled: v),
        ),
        const Divider(height: 1, color: AppColors.border, indent: 16),
        // Rule list
        ...settings.keywordHighlightRules.asMap().entries.map((entry) {
          final i = entry.key;
          final rule = entry.value;
          return Column(
            children: [
              _RuleRow(
                rule: rule,
                onToggle: (enabled) {
                  final updated = List<AppKeywordHighlightRule>.from(
                      settings.keywordHighlightRules);
                  updated[i] = rule.copyWith(enabled: enabled);
                  context
                      .read<SettingsProvider>()
                      .save(keywordHighlightRules: updated);
                },
                onEdit: () => _showRuleDialog(context, settings, rule: rule, index: i),
                onDelete: () {
                  final updated = List<AppKeywordHighlightRule>.from(
                      settings.keywordHighlightRules)
                    ..removeAt(i);
                  context
                      .read<SettingsProvider>()
                      .save(keywordHighlightRules: updated);
                },
              ),
              if (i < settings.keywordHighlightRules.length - 1)
                const Divider(height: 1, color: AppColors.border, indent: 16),
            ],
          );
        }),
        // Add rule button
        if (settings.keywordHighlightRules.length < kMaxKeywordHighlightRules)
          Column(
            children: [
              const Divider(height: 1, color: AppColors.border, indent: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.add, color: AppColors.accent, size: 18),
                title: const Text('Add rule',
                    style: TextStyle(color: AppColors.accent, fontSize: 13)),
                onTap: () => _showRuleDialog(context, settings),
              ),
            ],
          ),
        if (settings.keywordHighlightRules.length >= kMaxKeywordHighlightRules)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Maximum $kMaxKeywordHighlightRules rules reached.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Future<void> _showRuleDialog(
    BuildContext context,
    SettingsProvider settings, {
    AppKeywordHighlightRule? rule,
    int? index,
  }) async {
    final result = await showDialog<AppKeywordHighlightRule>(
      context: context,
      builder: (_) => _KeywordRuleDialog(initial: rule),
    );
    if (result == null || !context.mounted) return;
    final updated = List<AppKeywordHighlightRule>.from(settings.keywordHighlightRules);
    if (index != null) {
      updated[index] = result;
    } else {
      updated.add(result);
    }
    context.read<SettingsProvider>().save(keywordHighlightRules: updated);
  }
}

class _RuleRow extends StatelessWidget {
  final AppKeywordHighlightRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleRow({
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rule.background != null)
            _ColorDot(color: rule.background!, label: 'bg'),
          if (rule.foreground != null) ...[
            if (rule.background != null) const SizedBox(width: 4),
            _ColorDot(color: rule.foreground!, label: 'fg', border: true),
          ],
        ],
      ),
      title: Text(rule.label,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      subtitle: Text(
        '${rule.isRegex ? "regex" : "literal"}  ·  ${rule.pattern}',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: rule.enabled,
            onChanged: onToggle,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
            onPressed: onEdit,
            tooltip: 'Edit rule',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textSecondary),
            onPressed: onDelete,
            tooltip: 'Delete rule',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;

  const _ColorDot({required this.color, required this.label, this.border = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border
              ? Border.all(color: AppColors.textSecondary, width: 1.5)
              : null,
        ),
      ),
    );
  }
}

class _KeywordRuleDialog extends StatefulWidget {
  final AppKeywordHighlightRule? initial;
  const _KeywordRuleDialog({this.initial});

  @override
  State<_KeywordRuleDialog> createState() => _KeywordRuleDialogState();
}

class _KeywordRuleDialogState extends State<_KeywordRuleDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _patternCtrl;
  late bool _isRegex;
  late bool _caseSensitive;
  Color? _foreground;
  Color? _background;
  String? _regexError;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _labelCtrl = TextEditingController(text: r?.label ?? '');
    _patternCtrl = TextEditingController(text: r?.pattern ?? '');
    _isRegex = r?.isRegex ?? false;
    _caseSensitive = r?.caseSensitive ?? false;
    _foreground = r?.foreground;
    _background = r?.background;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _patternCtrl.dispose();
    super.dispose();
  }

  void _validatePattern() {
    if (!_isRegex) {
      setState(() => _regexError = null);
      return;
    }
    try {
      RegExp(_patternCtrl.text);
      setState(() => _regexError = null);
    } catch (e) {
      setState(() => _regexError = e.toString());
    }
  }

  bool get _isValid =>
      _labelCtrl.text.trim().isNotEmpty &&
      _patternCtrl.text.isNotEmpty &&
      _regexError == null &&
      (_foreground != null || _background != null);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        widget.initial == null ? 'Add rule' : 'Edit rule',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Label', _labelCtrl, hint: 'e.g. Error'),
            const SizedBox(height: 12),
            _field(
              'Pattern',
              _patternCtrl,
              hint: _isRegex ? r'e.g. \berror\b' : 'e.g. error',
              monospace: true,
              onChanged: (_) => _validatePattern(),
              errorText: _regexError,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _isRegex,
                  onChanged: (v) =>
                      setState(() => _isRegex = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('Regex',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                const SizedBox(width: 16),
                Checkbox(
                  value: _caseSensitive,
                  onChanged: (v) =>
                      setState(() => _caseSensitive = v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('Case-sensitive',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            _ColorPickerButton(
              label: 'Foreground (text color)',
              current: _foreground,
              presets: _kForegroundPresets,
              onChanged: (c) => setState(() => _foreground = c),
            ),
            const SizedBox(height: 8),
            _ColorPickerButton(
              label: 'Background',
              current: _background,
              presets: _kBackgroundPresets,
              onChanged: (c) => setState(() => _background = c),
            ),
            if (!_isValid && _labelCtrl.text.isNotEmpty && _patternCtrl.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Choose at least one color.',
                  style: TextStyle(color: Colors.red, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isValid
              ? () {
                  Navigator.pop(
                    context,
                    AppKeywordHighlightRule(
                      id: widget.initial?.id,
                      label: _labelCtrl.text.trim(),
                      pattern: _patternCtrl.text,
                      isRegex: _isRegex,
                      caseSensitive: _caseSensitive,
                      enabled: widget.initial?.enabled ?? true,
                      foreground: _foreground,
                      background: _background,
                    ),
                  );
                }
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool monospace = false,
    ValueChanged<String>? onChanged,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontFamily: monospace ? 'monospace' : null,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
            errorText: errorText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: const OutlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorPickerButton extends StatelessWidget {
  final String label;
  final Color? current;
  final List<Color> presets;
  final ValueChanged<Color?> onChanged;

  const _ColorPickerButton({
    required this.label,
    required this.current,
    required this.presets,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        GestureDetector(
          onTap: () => _pick(context),
          child: Container(
            width: 80,
            height: 28,
            decoration: BoxDecoration(
              color: current ?? Colors.transparent,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: current == null
                ? const Text('None',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11))
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showDialog<Color?>(
      context: context,
      builder: (_) => _ColorGridDialog(presets: presets, current: current),
    );
    // result == null means dialog dismissed; result == _clearSentinel means "None"
    if (result == _clearSentinel) {
      onChanged(null);
    } else if (result != null) {
      onChanged(result);
    }
  }
}

// Sentinel value returned by the dialog when the user picks "None"
final _clearSentinel = const Color(0x00000000);

class _ColorGridDialog extends StatelessWidget {
  final List<Color> presets;
  final Color? current;
  const _ColorGridDialog({required this.presets, required this.current});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Pick color',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // "None" option
          GestureDetector(
            onTap: () => Navigator.pop(context, _clearSentinel),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: const Text('✕',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ),
          ...presets.map((c) => GestureDetector(
                onTap: () => Navigator.pop(context, c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                    border: current == c
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add the keyword highlighting section to `settings_screen.dart`**

Add the import at the top of `settings_screen.dart`:
```dart
import 'keyword_highlight_settings.dart';
```

After the Terminal `_Section` (after line 148, around the `const SizedBox(height: 24)` before Recording), insert:

```dart
const SizedBox(height: 24),
_Section(title: 'Keyword Highlighting', children: [
  const KeywordHighlightSection(),
]),
```

- [ ] **Step 3: Verify the app compiles**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Run the app and test the settings UI manually**

```bash
cd app && flutter run -d macos
```

- Navigate to Settings → Terminal → scroll to "Keyword Highlighting"
- Toggle master enable off/on — verify terminal highlighting updates immediately
- Edit the "Error" rule — change background color — verify terminal updates
- Add a new rule with a literal pattern — type that word in a terminal session — verify highlight appears
- Add a rule with an invalid regex `[bad` — verify "Invalid regex" error appears inline
- Delete a rule — verify it disappears from terminal output

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/keyword_highlight_settings.dart app/lib/widgets/settings_screen.dart
git commit -m "feat: keyword highlighting settings UI — rule list, add/edit dialog, color picker"
```

---

### Task 9: Terminal config panel compact section

**Files:**
- Modify: `app/lib/widgets/terminal_config_panel.dart`

- [ ] **Step 1: Update `terminal_config_panel.dart`**

Replace the entire file:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/keyword_highlight_rule.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import 'terminal_appearance_controls.dart';
import 'workspace_side_panel.dart';

class TerminalConfigPanel extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onOpenSettings;

  const TerminalConfigPanel({super.key, this.onClose, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return WorkspaceSidePanel(
      title: 'Terminal',
      closeTooltip: 'Close terminal settings',
      onClose: onClose,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const TerminalAppearanceControls(
            layout: AppearanceControlsLayout.vertical,
          ),
          const SizedBox(height: 20),
          _KeywordHighlightCompact(onOpenSettings: onOpenSettings),
        ],
      ),
    );
  }
}

class _KeywordHighlightCompact extends StatelessWidget {
  final VoidCallback? onOpenSettings;
  const _KeywordHighlightCompact({this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KEYWORD HIGHLIGHTING',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        // Master toggle
        Row(
          children: [
            const Expanded(
              child: Text('Enable',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
            ),
            Switch(
              value: settings.keywordHighlightingEnabled,
              onChanged: (v) => context
                  .read<SettingsProvider>()
                  .save(keywordHighlightingEnabled: v),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Per-rule compact rows
        ...settings.keywordHighlightRules.asMap().entries.map((entry) {
          final i = entry.key;
          final rule = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                if (rule.background != null)
                  _Dot(color: rule.background!),
                if (rule.foreground != null) ...[
                  if (rule.background != null) const SizedBox(width: 4),
                  _Dot(color: rule.foreground!, border: true),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rule.label,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ),
                Switch(
                  value: rule.enabled,
                  onChanged: (v) {
                    final updated = List<AppKeywordHighlightRule>.from(
                        settings.keywordHighlightRules);
                    updated[i] = rule.copyWith(enabled: v);
                    context
                        .read<SettingsProvider>()
                        .save(keywordHighlightRules: updated);
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        // Link to full settings
        if (onOpenSettings != null)
          GestureDetector(
            onTap: onOpenSettings,
            child: const Text(
              'Manage rules in Settings →',
              style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  decoration: TextDecoration.underline),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final bool border;
  const _Dot({required this.color, this.border = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: border
            ? Border.all(color: AppColors.textSecondary, width: 1)
            : null,
      ),
    );
  }
}
```

- [ ] **Step 2: Wire `onOpenSettings` where `TerminalConfigPanel` is instantiated**

Find where `TerminalConfigPanel` is created (search for `TerminalConfigPanel(` in the codebase) and pass `onOpenSettings`:

```bash
grep -rn "TerminalConfigPanel(" app/lib/ --include="*.dart"
```

In the calling widget, add `onOpenSettings: () { /* navigate to Settings → Terminal */ }`. The exact navigation depends on the calling context — typically something like `context.read<SomeNavigationProvider>().navigateTo(NavSection.settings)` or similar. Check the calling file and use the existing navigation pattern.

- [ ] **Step 3: Verify the app compiles**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Step 4: Run the app and test manually**

```bash
cd app && flutter run -d macos
```

- Open a terminal session
- Click the tune icon to open the Terminal config panel
- Verify "KEYWORD HIGHLIGHTING" section appears with master toggle and per-rule toggles
- Toggle a rule off — verify the highlight disappears in the terminal immediately
- Toggle it back on — verify the highlight reappears

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/terminal_config_panel.dart
git commit -m "feat: terminal config panel — compact keyword highlight toggle section"
```

---

## Self-Review Checklist

- **Spec coverage:**
  - ✅ Global rules only — `SettingsProvider` holds one list, no per-host override
  - ✅ Both foreground + background color — `KeywordHighlightRule` has both nullable fields
  - ✅ Verbose defaults — 9 rules in `kDefaultKeywordHighlightRules`
  - ✅ Settings → Terminal section — `KeywordHighlightSection` in `settings_screen.dart`
  - ✅ Workspace side panel — `_KeywordHighlightCompact` in `terminal_config_panel.dart`
  - ✅ SSH + local shell — render layer is independent of `SshService`
  - ✅ Recordings unaffected — no data mutation
  - ✅ Max 20 rules enforced — `kMaxKeywordHighlightRules` in model + UI guard
  - ✅ Invalid regex gracefully handled — `toXtermRule()` returns null + dialog validates
  - ✅ Wide char handling — `if (charWidth == 2) i++` in `paintKeywordForeground`

- **Type consistency:**
  - `AppKeywordHighlightRule` throughout app layer
  - `xterm.KeywordHighlightRule` (from `packages/xterm`) throughout render layer
  - `kDefaultKeywordHighlightRules` and `kMaxKeywordHighlightRules` defined in `app/lib/models/keyword_highlight_rule.dart`
  - `save(keywordHighlightRules:, keywordHighlightingEnabled:)` in `SettingsProvider`
  - `_paintKeywordHighlights(canvas, firstLine, lastLine)` in `RenderTerminal`
  - `paintKeywordForeground(canvas, lineOffset, line, startCol, endCol, fgColor)` in `TerminalPainter`
