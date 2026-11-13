import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'package:yourssh_ui/yourssh_ui.dart';

import '../theme/mobile_tokens.dart';
import 'accessory_bar_controller.dart';

/// Mobile terminal accessory bar: special keys + sticky Ctrl/Alt above the
/// soft keyboard. Emits xterm [TerminalKey]s (with consumed modifiers) via
/// [onKey] and literal characters via [onText]. Dedicated `^C` / `^D` buttons
/// send the critical interrupts directly, independent of the sticky state.
class AccessoryKeyBar extends StatelessWidget {
  final AccessoryBarController controller;
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final void Function(String text) onText;

  /// Opens the terminal side panel (extended keyboard / snippets / history /
  /// themes). When null the leading keyboard button is hidden.
  final VoidCallback? onOpenPanel;

  const AccessoryKeyBar({
    super.key,
    required this.controller,
    required this.onKey,
    required this.onText,
    this.onOpenPanel,
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

  /// Dedicated `Ctrl+<key>` (e.g. ^C/^D). Clears any armed sticky modifier so
  /// it can't carry over to the next keypress.
  void _ctrlKey(TerminalKey k) {
    controller.consumeModifiers();
    onKey(k, ctrl: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: MobileTokens.accessoryBarHeight,
          color: YsColors.chrome,
          child: ListView(
            scrollDirection: Axis.horizontal,
            // 48 px bar - 2 x 2 px padding = 44 px key hit targets.
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            children: [
              if (onOpenPanel != null)
                _icon(FLucideIcons.keyboard, 'Keyboard panel', onOpenPanel!),
              _btn('Esc', onTap: () => _key(TerminalKey.escape)),
              _btn('Tab', onTap: () => _key(TerminalKey.tab)),
              _btn('Ctrl',
                  armed: controller.ctrlArmed, onTap: controller.armCtrl),
              _btn('Alt', armed: controller.altArmed, onTap: controller.armAlt),
              _btn('^C', onTap: () => _ctrlKey(TerminalKey.keyC)),
              _btn('^D', onTap: () => _ctrlKey(TerminalKey.keyD)),
              _icon(FLucideIcons.chevronLeft, 'Left',
                  () => _key(TerminalKey.arrowLeft)),
              _icon(FLucideIcons.chevronUp, 'Up',
                  () => _key(TerminalKey.arrowUp)),
              _icon(FLucideIcons.chevronDown, 'Down',
                  () => _key(TerminalKey.arrowDown)),
              _icon(FLucideIcons.chevronRight, 'Right',
                  () => _key(TerminalKey.arrowRight)),
              for (final ch in const ['/', '-', '|', '~', ':', '\$'])
                _btn(ch, onTap: () => _text(ch)),
            ],
          ),
        );
      },
    );
  }

  /// Minimum key size: the 44 px touch target (Review Focus 5).
  static const double _key44 = MobileTokens.touchTarget;

  Widget _btn(String label, {required VoidCallback onTap, bool armed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _key44, minHeight: _key44),
        child: FButton(
          size: .sm,
          variant: armed ? .primary : .secondary,
          onPress: onTap,
          child: Text(label),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minWidth: _key44, minHeight: _key44),
          child: FButton.icon(
            size: .sm,
            variant: .secondary,
            semanticsLabel: tooltip,
            onPress: onTap,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}
