import 'package:flutter/widgets.dart';
// Material's Tooltip is the tooltip used across the app's icon buttons.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show SelectableText, Tooltip;
import 'package:yourssh_ui/yourssh_ui.dart';

/// Icon-only button with a tooltip that doubles as the semantics label.
class WtIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPress;
  final Key? buttonKey;

  const WtIconButton({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: FButton.icon(
      key: buttonKey,
      variant: .ghost,
      size: .xs,
      semanticsLabel: tooltip,
      onPress: onPress,
      child: Icon(icon),
    ),
  );
}

/// Single-line text field in the small control size; monospace by default.
class WtField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool mono;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmit;
  final FocusNode? focusNode;
  final IconData? prefixIcon;

  /// Custom prefix (e.g. a progress indicator); wins over [prefixIcon].
  final Widget? prefix;

  const WtField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.mono = true,
    this.onChanged,
    this.onSubmit,
    this.focusNode,
    this.prefixIcon,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) => FTextField(
    control: .managed(
      controller: controller,
      onChange: onChanged == null ? null : (v) => onChanged!(v.text),
    ),
    focusNode: focusNode,
    size: .sm,
    hint: hint,
    obscureText: obscure,
    autocorrect: false,
    enableSuggestions: false,
    onSubmit: onSubmit,
    prefixBuilder: prefixIcon == null && prefix == null
        ? null
        : (context, style, variants) => Padding(
            padding: const EdgeInsets.only(left: YsSpace.s3),
            child: prefix ??
                Icon(prefixIcon, size: 16, color: YsColors.mutedForeground),
          ),
    style: mono
        ? .delta(
            contentTextStyle: .delta([
              .base(
                const .delta(
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                ),
              ),
            ]),
          )
        : const .context(),
  );
}

/// Multi-line, expanding code area (monospace).
class WtCodeArea extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;

  const WtCodeArea({super.key, required this.controller, this.hint});

  @override
  Widget build(BuildContext context) => FTextField.multiline(
    control: .managed(controller: controller),
    hint: hint,
    minLines: null,
    maxLines: null,
    expands: true,
    autocorrect: false,
    enableSuggestions: false,
    style: .delta(
      contentTextStyle: .delta([
        .base(
          const .delta(
            fontFamily: kYsMonoFontFamily,
            fontFamilyFallback: kYsMonoFontFallback,
            fontSize: 12,
          ),
        ),
      ]),
    ),
  );
}

/// Small muted caption.
class WtCaption extends StatelessWidget {
  final String text;
  const WtCaption(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: YsColors.mutedForeground, fontSize: 11),
  );
}

/// Centered muted message (empty states inside panels).
class WtHint extends StatelessWidget {
  final String text;
  const WtHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(YsSpace.s4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: YsColors.mutedForeground, fontSize: 12),
      ),
    ),
  );
}

/// Monospace body text style.
const TextStyle kWtMono = TextStyle(
  color: YsColors.foreground,
  fontSize: 12,
  fontFamily: kYsMonoFontFamily,
  fontFamilyFallback: kYsMonoFontFallback,
);

/// Toggle chip: filled when selected, outlined otherwise.
class WtChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const WtChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
    child: FButton(
      size: .xs,
      variant: selected ? .secondary : .outline,
      selected: selected,
      mainAxisSize: .min,
      onPress: onTap,
      child: Text(
        label,
        style: TextStyle(color: selected ? YsColors.primary : null),
      ),
    ),
  );
}

/// Selectable monospace text (output / body viewers).
class WtSelectableText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const WtSelectableText(this.text, {super.key, this.style = kWtMono});

  @override
  Widget build(BuildContext context) => SelectableText(text, style: style);
}
