import 'package:flutter/material.dart';

/// Rounded square tile with an OS / protocol glyph on a brand colour.
class YsOsTile extends StatelessWidget {
  final Widget glyph;
  final Color color;
  final double size;
  const YsOsTile({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('ys-os-tile'),
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * 0.22),
    ),
    child: IconTheme.merge(
      data: IconThemeData(color: Colors.white, size: size * 0.5),
      child: glyph,
    ),
  );
}
