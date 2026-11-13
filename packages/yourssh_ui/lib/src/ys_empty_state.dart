import 'package:flutter/material.dart';

import 'ys_colors.dart';
import 'ys_metrics.dart';

/// Centered icon + title + message + optional action for empty lists.
class YsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const YsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(YsSpace.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: YsColors.mutedForeground),
          const SizedBox(height: YsSpace.s3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: YsColors.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: YsSpace.s1),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 13,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: YsSpace.s4),
            action!,
          ],
        ],
      ),
    ),
  );
}
