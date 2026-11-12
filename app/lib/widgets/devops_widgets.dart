import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Single-line forui text field shared by the devops tool screens. Optional
/// monospace content, leading icon and Enter-to-submit.
class DevopsTextField extends StatelessWidget {
  const DevopsTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.mono = false,
    this.number = false,
    this.autofocus = false,
    this.onSubmit,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final bool mono;
  final bool number;
  final bool autofocus;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => FTextField(
    control: .managed(controller: controller),
    label: label == null ? null : Text(label!),
    hint: hint,
    autofocus: autofocus,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.done,
    keyboardType: number ? TextInputType.number : null,
    inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
    onSubmit: onSubmit == null ? null : (_) => onSubmit!(),
    prefixBuilder: icon == null
        ? null
        : (context, style, variants) => Padding(
            padding: const EdgeInsets.only(left: YsSpace.s3),
            child: Icon(icon, size: 16, color: YsColors.mutedForeground),
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

/// Muted caption used above a form block.
class DevopsCaption extends StatelessWidget {
  const DevopsCaption(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: YsColors.mutedForeground, fontSize: 12),
  );
}
