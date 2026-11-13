import 'package:flutter/material.dart';

/// Label for an `FButton` on a narrow phone: one line, ellipsised instead of
/// overflowing the button's content row. (`FButton` places its child straight
/// into a `Row`, so a bare `Text` that does not fit overflows.)
class ButtonLabel extends StatelessWidget {
  const ButtonLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
