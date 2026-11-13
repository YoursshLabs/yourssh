import 'package:flutter/material.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// Section title with an optional right-aligned muted summary.
class YsSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  const YsSectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: YsSpace.s2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: YsColors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null)
          Flexible(
            child: Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 12,
              ),
            ),
          ),
      ],
    ),
  );
}
