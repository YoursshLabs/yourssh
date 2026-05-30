import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/hotkey_service.dart';
import '../theme/app_theme.dart';

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

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Keyboard Shortcuts'),
          backgroundColor: AppColors.sidebar,
          foregroundColor: AppColors.textPrimary,
          actions: [
            if (_recording != null)
              TextButton(
                onPressed: _cancelRecording,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.orange),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            if (_recording != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.accent.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.keyboard, size: 14, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Press a key combo for "${_labels[_recording]}"  •  Esc to cancel',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                children: _labels.entries.map((entry) {
                  final isRecording = _recording == entry.key;
                  final current = settings.hotkeys[entry.key] ?? '';
                  return _HotkeyRow(
                    label: entry.value,
                    combo: current,
                    isRecording: isRecording,
                    onTap: () => _startRecording(entry.key),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Click a shortcut to rebind it. Changes are saved immediately.',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotkeyRow extends StatefulWidget {
  final String label;
  final String combo;
  final bool isRecording;
  final VoidCallback onTap;

  const _HotkeyRow({
    required this.label,
    required this.combo,
    required this.isRecording,
    required this.onTap,
  });

  @override
  State<_HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends State<_HotkeyRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: widget.isRecording
                ? AppColors.accent.withValues(alpha: 0.08)
                : _hovered
                    ? AppColors.card
                    : Colors.transparent,
            border: const Border(
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.isRecording
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.card,
                  border: Border.all(
                    color: widget.isRecording ? AppColors.accent : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  widget.isRecording ? 'recording...' : widget.combo,
                  style: TextStyle(
                    color: AppColors.accent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontStyle:
                        widget.isRecording ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.edit_outlined,
                size: 13,
                color: _hovered || widget.isRecording
                    ? AppColors.textSecondary
                    : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
