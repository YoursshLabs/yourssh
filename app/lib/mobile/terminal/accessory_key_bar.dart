import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';
import 'accessory_bar_controller.dart';

/// Mobile terminal accessory bar: special keys + sticky Ctrl/Alt above the
/// soft keyboard. Emits xterm [TerminalKey]s (with consumed modifiers) via
/// [onKey] and literal characters via [onText]. Dedicated `^C` / `^D` buttons
/// send the critical interrupts directly, independent of the sticky state.
class AccessoryKeyBar extends StatelessWidget {
  final AccessoryBarController controller;
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final void Function(String text) onText;

  const AccessoryKeyBar({
    super.key,
    required this.controller,
    required this.onKey,
    required this.onText,
  });

  /// Emit a special key, applying (and clearing) any armed sticky modifiers.
  void _key(TerminalKey k) {
    final m = controller.consumeModifiers();
    onKey(k, ctrl: m.ctrl, alt: m.alt);
  }

  /// Emit a literal character; armed modifiers are consumed (cleared) since
  /// plain text carries no Ctrl/Alt.
  void _text(String s) {
    controller.consumeModifiers();
    onText(s);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: 46,
          color: AppColors.card,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            children: [
              _btn('Esc', onTap: () => _key(TerminalKey.escape)),
              _btn('Tab', onTap: () => _key(TerminalKey.tab)),
              _btn('Ctrl',
                  armed: controller.ctrlArmed, onTap: controller.armCtrl),
              _btn('Alt', armed: controller.altArmed, onTap: controller.armAlt),
              _btn('^C', onTap: () => onKey(TerminalKey.keyC, ctrl: true)),
              _btn('^D', onTap: () => onKey(TerminalKey.keyD, ctrl: true)),
              _icon(Icons.keyboard_arrow_left, 'Left',
                  () => _key(TerminalKey.arrowLeft)),
              _icon(Icons.keyboard_arrow_up, 'Up',
                  () => _key(TerminalKey.arrowUp)),
              _icon(Icons.keyboard_arrow_down, 'Down',
                  () => _key(TerminalKey.arrowDown)),
              _icon(Icons.keyboard_arrow_right, 'Right',
                  () => _key(TerminalKey.arrowRight)),
              for (final ch in const ['/', '-', '|', '~', ':'])
                _btn(ch, onTap: () => _text(ch)),
            ],
          ),
        );
      },
    );
  }

  Widget _btn(String label, {required VoidCallback onTap, bool armed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: armed ? AppColors.accent : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: armed ? Colors.black : AppColors.textPrimary,
                  fontSize: 14)),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}
