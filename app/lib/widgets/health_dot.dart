import 'package:flutter/material.dart';
import '../models/session_health.dart';
import '../theme/app_theme.dart';

/// 7px connection-health dot. Static color per tone; [BadgeTone.connecting]
/// pulses to signal an in-progress (re)connect.
class HealthDot extends StatefulWidget {
  final BadgeTone tone;
  const HealthDot({super.key, required this.tone});

  @override
  State<HealthDot> createState() => _HealthDotState();
}

class _HealthDotState extends State<HealthDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(HealthDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tone != widget.tone) _syncPulse();
  }

  void _syncPulse() {
    if (widget.tone == BadgeTone.connecting) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color _color(BadgeTone tone) {
    switch (tone) {
      case BadgeTone.green:
        return AppColors.success;
      case BadgeTone.amber:
      case BadgeTone.connecting:
        return AppColors.orange;
      case BadgeTone.red:
        return AppColors.red;
      case BadgeTone.grey:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      key: const Key('health-dot'),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: _color(widget.tone),
        shape: BoxShape.circle,
      ),
    );
    if (widget.tone != BadgeTone.connecting) return dot;
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse),
      child: dot,
    );
  }
}
