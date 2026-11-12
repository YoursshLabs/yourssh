import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../providers/settings_provider.dart';
import '../../services/hotkey_service.dart';
import 'settings_tiles.dart';

/// Keyboard Shortcuts: click (or Enter on) a row, then press the new combo;
/// Esc or Cancel stops recording. Saved immediately.
class HotkeySettingsScreen extends StatefulWidget {
  const HotkeySettingsScreen({super.key});

  @override
  State<HotkeySettingsScreen> createState() => _HotkeySettingsScreenState();
}

class _HotkeySettingsScreenState extends State<HotkeySettingsScreen> {
  String? _recording; // action key being recorded
  final _focusNode = FocusNode();

  static const _labels = {
    'command_palette': 'Command Palette',
    'new_session': 'New Session',
    'close_session': 'Close Session',
    'next_session': 'Next Session',
    'prev_session': 'Previous Session',
    'toggle_input_bar': 'Toggle Input Bar',
    'split_horizontal': 'Split Horizontal',
    'split_vertical': 'Split Vertical',
  };

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording(String action) {
    setState(() => _recording = action);
    _focusNode.requestFocus();
  }

  void _cancelRecording() => setState(() => _recording = null);

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (_recording == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    final key = event.logicalKey;

    // Esc cancels
    if (key == LogicalKeyboardKey.escape) {
      _cancelRecording();
      return KeyEventResult.handled;
    }

    // Ignore bare modifier presses
    final modifierKeys = {
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.meta,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (modifierKeys.contains(key)) return KeyEventResult.handled;

    // Build combo string
    final parts = <String>[];
    final hw = HardwareKeyboard.instance;
    if (hw.isControlPressed) parts.add('ctrl');
    if (hw.isShiftPressed) parts.add('shift');
    if (hw.isAltPressed) parts.add('alt');
    if (hw.isMetaPressed) parts.add('meta');

    final keyName = _logicalKeyName(key);
    if (keyName == null) return KeyEventResult.handled;
    parts.add(keyName);

    final combo = parts.join('+');

    // Validate it can be parsed back
    if (HotkeyService.parse(combo) == null) return KeyEventResult.handled;

    final settings = context.read<SettingsProvider>();
    final updated = Map<String, String>.from(settings.hotkeys)
      ..[_recording!] = combo;
    settings.save(hotkeys: updated);

    setState(() => _recording = null);
    return KeyEventResult.handled;
  }

  String? _logicalKeyName(LogicalKeyboardKey key) {
    final map = {
      LogicalKeyboardKey.keyA: 'a',
      LogicalKeyboardKey.keyB: 'b',
      LogicalKeyboardKey.keyC: 'c',
      LogicalKeyboardKey.keyD: 'd',
      LogicalKeyboardKey.keyE: 'e',
      LogicalKeyboardKey.keyF: 'f',
      LogicalKeyboardKey.keyG: 'g',
      LogicalKeyboardKey.keyH: 'h',
      LogicalKeyboardKey.keyI: 'i',
      LogicalKeyboardKey.keyJ: 'j',
      LogicalKeyboardKey.keyK: 'k',
      LogicalKeyboardKey.keyL: 'l',
      LogicalKeyboardKey.keyM: 'm',
      LogicalKeyboardKey.keyN: 'n',
      LogicalKeyboardKey.keyO: 'o',
      LogicalKeyboardKey.keyP: 'p',
      LogicalKeyboardKey.keyQ: 'q',
      LogicalKeyboardKey.keyR: 'r',
      LogicalKeyboardKey.keyS: 's',
      LogicalKeyboardKey.keyT: 't',
      LogicalKeyboardKey.keyU: 'u',
      LogicalKeyboardKey.keyV: 'v',
      LogicalKeyboardKey.keyW: 'w',
      LogicalKeyboardKey.keyX: 'x',
      LogicalKeyboardKey.keyY: 'y',
      LogicalKeyboardKey.keyZ: 'z',
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
      LogicalKeyboardKey.tab: 'tab',
      LogicalKeyboardKey.enter: 'enter',
      LogicalKeyboardKey.escape: 'esc',
      LogicalKeyboardKey.space: 'space',
      LogicalKeyboardKey.backspace: 'backspace',
      LogicalKeyboardKey.delete: 'del',
      LogicalKeyboardKey.arrowUp: 'up',
      LogicalKeyboardKey.arrowDown: 'down',
      LogicalKeyboardKey.arrowLeft: 'left',
      LogicalKeyboardKey.arrowRight: 'right',
      LogicalKeyboardKey.f1: 'f1',
      LogicalKeyboardKey.f2: 'f2',
      LogicalKeyboardKey.f3: 'f3',
      LogicalKeyboardKey.f4: 'f4',
      LogicalKeyboardKey.f5: 'f5',
      LogicalKeyboardKey.f6: 'f6',
      LogicalKeyboardKey.f7: 'f7',
      LogicalKeyboardKey.f8: 'f8',
      LogicalKeyboardKey.f9: 'f9',
      LogicalKeyboardKey.f10: 'f10',
      LogicalKeyboardKey.f11: 'f11',
      LogicalKeyboardKey.f12: 'f12',
    };
    return map[key];
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final recording = _recording;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Material(
        color: YsColors.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
              decoration: const BoxDecoration(
                color: YsColors.sidebar,
                border: Border(bottom: BorderSide(color: YsColors.border)),
              ),
              child: Row(
                children: [
                  SettingsIconButton(
                    icon: FLucideIcons.arrowLeft,
                    tooltip: 'Back',
                    onPress: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: YsSpace.s2),
                  const Expanded(
                    child: Text(
                      'Keyboard Shortcuts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: YsColors.foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (recording != null)
                    FButton(
                      key: const ValueKey('hotkey-cancel'),
                      variant: .ghost,
                      size: .sm,
                      mainAxisSize: MainAxisSize.min,
                      onPress: _cancelRecording,
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ),
            if (recording != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: YsSpace.s4,
                  vertical: 10,
                ),
                color: YsColors.primary.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(
                      FLucideIcons.keyboard,
                      size: 14,
                      color: YsColors.primary,
                    ),
                    const SizedBox(width: YsSpace.s2),
                    Expanded(
                      child: Text(
                        'Press a key combo for "${_labels[recording]}"  •  Esc to cancel',
                        style: const TextStyle(
                          color: YsColors.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(YsSpace.s5),
                children: [
                  FTileGroup(
                    children: [
                      for (final entry in _labels.entries)
                        _hotkeyTile(
                          action: entry.key,
                          label: entry.value,
                          combo: settings.hotkeys[entry.key] ?? '',
                          isRecording: recording == entry.key,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(YsSpace.s4),
              child: Text(
                'Click a shortcut to rebind it. Changes are saved immediately.',
                style: TextStyle(color: YsColors.mutedForeground, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  FTile _hotkeyTile({
    required String action,
    required String label,
    required String combo,
    required bool isRecording,
  }) {
    return FTile(
      key: ValueKey('hotkey-row-$action'),
      selected: isRecording,
      onPress: () => _startRecording(action),
      title: Text(label),
      suffix: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isRecording
                  ? YsColors.primary.withValues(alpha: 0.15)
                  : YsColors.secondary,
              border: Border.all(
                color: isRecording ? YsColors.primary : YsColors.border,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              isRecording ? 'recording...' : combo,
              style: TextStyle(
                color: YsColors.accentText,
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
                fontSize: 12,
                fontStyle: isRecording ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          const Icon(
            FLucideIcons.pencil,
            size: 13,
            color: YsColors.mutedForeground,
          ),
        ],
      ),
    );
  }
}
