part of 'host_detail_panel.dart';

// ── Shared field widgets ──────────────────────────────────

/// Upper-case section caption ("GENERAL", "CREDENTIALS", …) with an
/// optional trailing action.
class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final caption = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: YsColors.mutedForeground,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: YsSpace.s5, bottom: YsSpace.s2),
      child: trailing == null
          ? caption
          : Row(
              children: [
                Expanded(child: caption),
                Flexible(flex: 3, child: trailing!),
              ],
            ),
    );
  }
}

/// Button label that ellipsizes instead of overflowing when the button is
/// squeezed (e.g. long labels at the 900 px window minimum).
Widget _buttonText(String text) =>
    Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis));

/// Vertical gap between the fields of one section.
const _fieldGap = SizedBox(height: YsSpace.s3);

/// Leading icon inside a field, in the field's icon style.
FFieldIconBuilder<FTextFieldStyle>? _prefixIcon(IconData? icon) => icon == null
    ? null
    : (context, style, variants) =>
          FTextField.prefixIconBuilder(context, style, variants, Icon(icon));

/// One single-line text field: optional [label] above, [hint] inside,
/// optional leading [icon]. Enter runs [onSubmit] (the form's save).
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final VoidCallback? onSubmit;

  const _Field({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => FTextFormField(
    control: .managed(controller: controller),
    label: label == null ? null : Text(label!),
    hint: hint,
    autofocus: autofocus,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    autocorrect: false,
    enableSuggestions: false,
    validator: validator,
    // Once Save has flagged a field, re-check it as the user edits so the
    // error goes away as soon as the value is valid.
    autovalidateMode: AutovalidateMode.onUserInteraction,
    // Keep the caret in the field (no unfocus) when Enter hits an invalid
    // form; a valid save closes the panel anyway.
    onEditingComplete: onSubmit == null ? null : controller.clearComposing,
    onSubmit: onSubmit == null ? null : (_) => onSubmit!(),
    prefixBuilder: _prefixIcon(icon),
  );
}

/// Password field with the show/hide toggle (tooltipped). Enter runs
/// [onSubmit].
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String? label;
  final IconData? icon;
  final VoidCallback? onSubmit;

  const _PasswordField({
    super.key,
    required this.controller,
    this.label,
    this.icon,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => FTextFormField.password(
    control: .managed(controller: controller),
    label: label == null ? null : Text(label!),
    hint: 'Password',
    textInputAction: TextInputAction.done,
    autofillHints: const [],
    onEditingComplete: onSubmit == null ? null : controller.clearComposing,
    onSubmit: onSubmit == null ? null : (_) => onSubmit!(),
    prefixBuilder: icon == null
        ? null
        : (context, style, _, variants) => FTextField.prefixIconBuilder(
            context,
            style,
            variants,
            Icon(icon),
          ),
    suffixBuilder: (context, style, obscure, variants) => Tooltip(
      message: obscure.value ? 'Show password' : 'Hide password',
      // The eye button already announces show/hide.
      excludeFromSemantics: true,
      child: FTextField.defaultObscureIconBuilder(
        context,
        style,
        obscure,
        variants,
      ),
    ),
  );
}

/// [FSelect] over a fixed list of `(value, text)` options. The select's own
/// value is the option index, so an option may be `null` (e.g. "follow
/// global", "Direct connection") and duplicate texts stay distinct. A
/// [value] that is not among the options shows the [hint].
class _Select<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;
  final String? hint;
  final IconData? icon;

  const _Select({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final index = options.indexWhere((o) => o.$1 == value);
    return FSelect<int>.rich(
      control: .lifted(
        value: index < 0 ? null : index,
        onChange: (i) {
          if (i != null) onChanged(options[i].$1);
        },
      ),
      format: (i) => options[i].$2,
      label: label == null ? null : Text(label!),
      hint: hint,
      prefixBuilder: _prefixIcon(icon),
      children: [
        for (final (i, (_, text)) in options.indexed)
          FSelectItem<int>(title: Text(text), value: i),
      ],
    );
  }
}

/// One option switch (label + description) for an [FTileGroup]. A press
/// anywhere on the row toggles it; the switch is the single focus stop.
FTile _switchTile({
  required Key key,
  required String title,
  Widget? titleWidget,
  required String description,
  required bool value,
  required ValueChanged<bool> onChange,
}) => switchRowTile(
  key: key,
  label: titleWidget ?? Text(title),
  description: Text(description),
  value: value,
  onChange: onChange,
);
