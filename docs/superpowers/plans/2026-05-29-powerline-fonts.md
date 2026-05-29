# Powerline Fonts Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bundle 6 Powerline fonts as assets and expose a font picker (dropdown + custom text field) in Settings, applied live to all terminal views.

**Architecture:** Font files live in `assets/fonts/powerline/`, registered in `pubspec.yaml`. `SettingsProvider` gains a `terminalFont` string field. `settings_screen.dart` adds a font row (dropdown + conditional custom input). All `TerminalView` usages read `settings.terminalFont`.

**Tech Stack:** Flutter, xterm ^4.0.0, shared_preferences ^2.3.2, powerline/fonts TTF/OTF files.

---

## File Map

| File | Action |
|---|---|
| `app/assets/fonts/powerline/*.ttf / *.otf` | Create — 6 font files |
| `app/pubspec.yaml` | Modify — register fonts under `flutter: fonts:` |
| `app/lib/providers/settings_provider.dart` | Modify — add `terminalFont` field + persist |
| `app/test/settings_provider_test.dart` | Create — unit tests for `terminalFont` |
| `app/lib/widgets/settings_screen.dart` | Modify — font dropdown + custom input row |
| `app/lib/widgets/terminal_view.dart` | Modify — use `settings.terminalFont` |
| `app/lib/widgets/local_terminal_screen.dart` | Modify — add SettingsProvider + use `terminalFont` |

---

## Task 1: Download Powerline Font Files

**Files:**
- Create: `app/assets/fonts/powerline/` (6 font files)

- [ ] **Step 1: Create fonts directory and download**

```bash
mkdir -p app/assets/fonts/powerline

curl -L -o "app/assets/fonts/powerline/DejaVu Sans Mono for Powerline.ttf" \
  "https://github.com/powerline/fonts/raw/master/DejaVuSansMono/DejaVu%20Sans%20Mono%20for%20Powerline.ttf"

curl -L -o "app/assets/fonts/powerline/Inconsolata for Powerline.otf" \
  "https://github.com/powerline/fonts/raw/master/Inconsolata/Inconsolata%20for%20Powerline.otf"

curl -L -o "app/assets/fonts/powerline/Meslo LG S Regular for Powerline.ttf" \
  "https://github.com/powerline/fonts/raw/master/Meslo%20Slashed/Meslo%20LG%20S%20Regular%20for%20Powerline.ttf"

curl -L -o "app/assets/fonts/powerline/Source Code Pro for Powerline.otf" \
  "https://github.com/powerline/fonts/raw/master/SourceCodePro/Source%20Code%20Pro%20for%20Powerline.otf"

curl -L -o "app/assets/fonts/powerline/Ubuntu Mono derivative Powerline.ttf" \
  "https://github.com/powerline/fonts/raw/master/UbuntuMono/Ubuntu%20Mono%20derivative%20Powerline.ttf"

curl -L -o "app/assets/fonts/powerline/Roboto Mono for Powerline.ttf" \
  "https://github.com/powerline/fonts/raw/master/RobotoMono/Roboto%20Mono%20for%20Powerline.ttf"
```

- [ ] **Step 2: Verify all 6 files downloaded and are non-empty**

```bash
ls -lh app/assets/fonts/powerline/
```

Expected: 6 files, each > 50KB. If any file is tiny (HTML error page), check the URL — look at the actual repo folder names at `https://github.com/powerline/fonts` and adjust. Common issues: folder name has a space (e.g. `Meslo%20LG` vs `Meslo%20Slashed`), or `.ttf` vs `.otf` mismatch.

- [ ] **Step 3: Commit font assets**

```bash
git add app/assets/fonts/
git commit -m "feat: add powerline font assets"
```

---

## Task 2: Register Fonts in pubspec.yaml

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Open `app/pubspec.yaml` and locate the `flutter:` section**

It currently looks like:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/monaco_editor.html
```

- [ ] **Step 2: Add font entries after `assets:`**

Replace the `flutter:` section with:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/monaco_editor.html
  fonts:
    - family: DejaVu Sans Mono for Powerline
      fonts:
        - asset: assets/fonts/powerline/DejaVu Sans Mono for Powerline.ttf
    - family: Inconsolata for Powerline
      fonts:
        - asset: assets/fonts/powerline/Inconsolata for Powerline.otf
    - family: Meslo LG S for Powerline
      fonts:
        - asset: assets/fonts/powerline/Meslo LG S Regular for Powerline.ttf
    - family: Source Code Pro for Powerline
      fonts:
        - asset: assets/fonts/powerline/Source Code Pro for Powerline.otf
    - family: Ubuntu Mono derivative Powerline
      fonts:
        - asset: assets/fonts/powerline/Ubuntu Mono derivative Powerline.ttf
    - family: Roboto Mono for Powerline
      fonts:
        - asset: assets/fonts/powerline/Roboto Mono for Powerline.ttf
```

> **Note:** The `family` name here is what you pass as `fontFamily` in Dart code. It must match exactly (case-sensitive).

- [ ] **Step 3: Verify pubspec parses cleanly**

```bash
cd app && flutter pub get
```

Expected: No errors. If you see "Unable to find asset", the file name in `asset:` doesn't match the actual filename — fix the pubspec entry.

- [ ] **Step 4: Commit**

```bash
git add app/pubspec.yaml
git commit -m "feat: register powerline fonts in pubspec"
```

---

## Task 3: Add terminalFont to SettingsProvider (TDD)

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Create: `app/test/settings_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Create `app/test/settings_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('terminalFont defaults to monospace', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalFont, 'monospace');
  });

  test('save persists terminalFont', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(terminalFont: 'DejaVu Sans Mono for Powerline');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('terminalFont'), 'DejaVu Sans Mono for Powerline');
    expect(provider.terminalFont, 'DejaVu Sans Mono for Powerline');
  });

  test('loads persisted terminalFont on init', () async {
    SharedPreferences.setMockInitialValues({
      'terminalFont': 'Inconsolata for Powerline',
    });
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.terminalFont, 'Inconsolata for Powerline');
  });
}
```

- [ ] **Step 2: Run tests — expect compile errors (field doesn't exist yet)**

```bash
cd app && flutter test test/settings_provider_test.dart
```

Expected: Compilation errors about missing `terminalFont`.

- [ ] **Step 3: Add `terminalFont` to `SettingsProvider`**

Open `app/lib/providers/settings_provider.dart`. Make these changes:

Add the field after `tmuxEnabled`:
```dart
String terminalFont = 'monospace';
```

In `_load()`, add after the `tmuxEnabled` line:
```dart
terminalFont = prefs.getString('terminalFont') ?? 'monospace';
```

In `save()`, add the parameter:
```dart
Future<void> save({
  bool? autoReconnect,
  int? reconnectAttempts,
  double? fontSize,
  String? terminalTheme,
  Map<String, String>? hotkeys,
  bool? networkStatsEnabled,
  bool? tmuxEnabled,
  String? terminalFont,
}) async {
  if (autoReconnect != null) this.autoReconnect = autoReconnect;
  if (reconnectAttempts != null) this.reconnectAttempts = reconnectAttempts;
  if (fontSize != null) this.fontSize = fontSize;
  if (terminalTheme != null) this.terminalTheme = terminalTheme;
  if (hotkeys != null) this.hotkeys = hotkeys;
  if (networkStatsEnabled != null) this.networkStatsEnabled = networkStatsEnabled;
  if (tmuxEnabled != null) this.tmuxEnabled = tmuxEnabled;
  if (terminalFont != null) this.terminalFont = terminalFont;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('autoReconnect', this.autoReconnect);
  await prefs.setInt('reconnectAttempts', this.reconnectAttempts);
  await prefs.setDouble('fontSize', this.fontSize);
  await prefs.setString('terminalTheme', this.terminalTheme);
  await prefs.setString('hotkeys', jsonEncode(this.hotkeys));
  await prefs.setBool('networkStatsEnabled', this.networkStatsEnabled);
  await prefs.setBool('tmuxEnabled', this.tmuxEnabled);
  await prefs.setString('terminalFont', this.terminalFont);
  notifyListeners();
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd app && flutter test test/settings_provider_test.dart
```

Expected:
```
00:00 +3: All tests passed!
```

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/settings_provider_test.dart
git commit -m "feat: add terminalFont to SettingsProvider"
```

---

## Task 4: Add Font Picker to Settings Screen

**Files:**
- Modify: `app/lib/widgets/settings_screen.dart`

- [ ] **Step 1: Add constants and controller to `_SettingsScreenState`**

In `settings_screen.dart`, find `_SettingsScreenState` and add after the `_themes` constant:

```dart
static const _bundledFonts = [
  'monospace',
  'DejaVu Sans Mono for Powerline',
  'Inconsolata for Powerline',
  'Meslo LG S for Powerline',
  'Source Code Pro for Powerline',
  'Ubuntu Mono derivative Powerline',
  'Roboto Mono for Powerline',
];
static const _kCustom = '__custom__';

final _customFontController = TextEditingController();
bool _pendingCustom = false;
```

- [ ] **Step 2: Add dispose for the controller**

The class already has no `dispose`. Add it:

```dart
@override
void dispose() {
  _customFontController.dispose();
  super.dispose();
}
```

- [ ] **Step 3: Add font rows to the Terminal section in `build()`**

Find the Terminal section in `build()`:

```dart
_Section(title: 'Terminal', children: [
  _Row(
    label: 'Color theme',
    ...
  ),
  _Row(
    label: 'Font size: ${settings.fontSize.round()}pt',
    ...
  ),
]),
```

Replace it with (add 2 new rows after font size):

```dart
_Section(title: 'Terminal', children: [
  _Row(
    label: 'Color theme',
    trailing: _DropDown<String>(
      value: settings.terminalTheme,
      items: _themes,
      labelOf: (t) => t,
      onChanged: (v) => context.read<SettingsProvider>().save(terminalTheme: v),
    ),
  ),
  _Row(
    label: 'Font size: ${settings.fontSize.round()}pt',
    trailing: SizedBox(
      width: 200,
      child: Slider(
        value: settings.fontSize,
        min: 10,
        max: 24,
        divisions: 14,
        onChanged: (v) => context.read<SettingsProvider>().save(fontSize: v),
      ),
    ),
  ),
  _Row(
    label: 'Terminal font',
    trailing: _buildFontDropdown(context, settings),
  ),
  if (_pendingCustom || !_bundledFonts.contains(settings.terminalFont))
    _Row(
      label: 'Custom font name',
      trailing: SizedBox(
        width: 220,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customFontController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'e.g. Hack Nerd Font',
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () {
                final name = _customFontController.text.trim();
                if (name.isEmpty) return;
                setState(() => _pendingCustom = false);
                context.read<SettingsProvider>().save(terminalFont: name);
              },
              child: const Text('Apply', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    ),
]),
```

- [ ] **Step 4: Add the `_buildFontDropdown` helper method to `_SettingsScreenState`**

Add this method to the class (after `build`):

```dart
Widget _buildFontDropdown(BuildContext context, SettingsProvider settings) {
  final isCustom = !_bundledFonts.contains(settings.terminalFont);
  if (isCustom && !_pendingCustom && _customFontController.text.isEmpty) {
    _customFontController.text = settings.terminalFont;
  }
  final ddValue = (isCustom || _pendingCustom) ? _kCustom : settings.terminalFont;
  return DropdownButton<String>(
    value: ddValue,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
    dropdownColor: AppColors.card,
    underline: const SizedBox(),
    items: [
      ..._bundledFonts.map((f) => DropdownMenuItem(
        value: f,
        child: Text(f == 'monospace' ? 'System Default' : f, style: const TextStyle(fontSize: 12)),
      )),
      const DropdownMenuItem(
        value: _kCustom,
        child: Text('Custom…', style: TextStyle(fontSize: 12)),
      ),
    ],
    onChanged: (v) {
      if (v == _kCustom) {
        setState(() {
          _pendingCustom = true;
          _customFontController.clear();
        });
      } else if (v != null) {
        setState(() => _pendingCustom = false);
        context.read<SettingsProvider>().save(terminalFont: v);
      }
    },
  );
}
```

- [ ] **Step 5: Verify no analysis errors**

```bash
cd app && flutter analyze lib/widgets/settings_screen.dart
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/settings_screen.dart
git commit -m "feat: add font picker to Settings screen"
```

---

## Task 5: Wire Terminal Views to Selected Font

**Files:**
- Modify: `app/lib/widgets/terminal_view.dart:50-54`
- Modify: `app/lib/widgets/local_terminal_screen.dart:104`

- [ ] **Step 1: Update `terminal_view.dart` — use `settings.terminalFont`**

In `terminal_view.dart`, find `_TerminalWidget.build()`. The current code at line ~50:

```dart
textStyle: TerminalStyle(
  fontSize: settings.fontSize,
  fontFamily: 'monospace',
),
```

Replace `'monospace'` with `settings.terminalFont`:

```dart
textStyle: TerminalStyle(
  fontSize: settings.fontSize,
  fontFamily: settings.terminalFont,
),
```

- [ ] **Step 2: Update `local_terminal_screen.dart` — inject SettingsProvider**

In `local_terminal_screen.dart`, find the `_buildTerminalView` method (or wherever `TerminalView(session.terminal)` is called — line ~104).

The current code:
```dart
return TerminalView(session.terminal);
```

Replace with:
```dart
final settings = context.watch<SettingsProvider>();
return TerminalView(
  session.terminal,
  textStyle: TerminalStyle(
    fontSize: settings.fontSize,
    fontFamily: settings.terminalFont,
  ),
);
```

Also add the import at the top of `local_terminal_screen.dart` if not already present:
```dart
import 'package:xterm/xterm.dart';
import '../providers/settings_provider.dart';
```

> Check whether `xterm` is already imported — the file uses `TerminalView` so `xterm` is already there, but `settings_provider.dart` may need to be added.

- [ ] **Step 3: Verify no analysis errors**

```bash
cd app && flutter analyze lib/widgets/terminal_view.dart lib/widgets/local_terminal_screen.dart
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/terminal_view.dart app/lib/widgets/local_terminal_screen.dart
git commit -m "feat: apply terminalFont setting to all terminal views"
```

---

## Task 6: Full Analysis + Smoke Test

- [ ] **Step 1: Run all tests**

```bash
cd app && flutter test
```

Expected: All tests pass (including the 3 new settings_provider_test).

- [ ] **Step 2: Run flutter analyze on the whole project**

```bash
cd app && flutter analyze
```

Expected: No errors (warnings are acceptable).

- [ ] **Step 3: Build check**

```bash
cd app && flutter build macos --debug 2>&1 | tail -5
```

Expected: `Build complete.` (or similar success message). If there's a font asset error, the pubspec `asset:` path doesn't match the actual filename — fix accordingly.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve any font asset path issues"
```
