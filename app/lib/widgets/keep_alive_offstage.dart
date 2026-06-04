import 'package:flutter/material.dart';

/// Lazily mounts [child] on first activation, then keeps it mounted
/// (offstage) when deactivated so its State survives navigation away
/// and back — e.g. the SFTP workspace keeping its connected session
/// while the user visits other tabs (issue #42).
class KeepAliveOffstage extends StatefulWidget {
  final bool active;
  final Widget child;

  const KeepAliveOffstage({super.key, required this.active, required this.child});

  @override
  State<KeepAliveOffstage> createState() => _KeepAliveOffstageState();
}

class _KeepAliveOffstageState extends State<KeepAliveOffstage> {
  bool _everActive = false;

  @override
  Widget build(BuildContext context) {
    _everActive = _everActive || widget.active;
    if (!_everActive) return const SizedBox.shrink();
    return Offstage(
      offstage: !widget.active,
      // Pause animations while hidden.
      child: TickerMode(enabled: widget.active, child: widget.child),
    );
  }
}
