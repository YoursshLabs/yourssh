import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'ys_colors.dart';

/// Semantic colour of a [YsStatusBadge].
enum YsStatus { neutral, ok, warn, error, accent }

Color _statusColor(YsStatus s) => switch (s) {
  YsStatus.neutral => YsColors.mutedForeground,
  YsStatus.ok => YsColors.ok,
  YsStatus.warn => YsColors.warn,
  YsStatus.error => YsColors.error,
  YsStatus.accent => YsColors.accentText,
};

/// Small neutral tag chip (host tags), over a secondary [FBadge].
class YsTag extends StatelessWidget {
  final String label;
  const YsTag(this.label, {super.key});

  @override
  Widget build(BuildContext context) => FBadge(
    variant: .secondary,
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}

/// Outlined status chip (RDP, lag, ...), label coloured by [status].
class YsStatusBadge extends StatelessWidget {
  final String label;
  final YsStatus status;
  const YsStatusBadge(this.label, {super.key, this.status = YsStatus.neutral});

  @override
  Widget build(BuildContext context) => FBadge(
    variant: .outline,
    style: .delta(labelTextStyle: .delta(color: _statusColor(status))),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
