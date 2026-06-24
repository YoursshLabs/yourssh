import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/connection_log.dart';
import '../models/host.dart';
import '../models/ssh_session.dart';
import '../services/os_detection.dart';
import '../theme/app_theme.dart';

/// Full-area screen shown inside a session tab while an SSH session is
/// connecting, has errored, or has disconnected. Mirrors mstsc-style connect
/// UX: a host card, an animated node → line → terminal connection graphic, a
/// "Show logs" panel over [SshSession.connectionLog], and Close/Retry actions.
class SessionConnectingView extends StatefulWidget {
  final SshSession session;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  const SessionConnectingView({
    super.key,
    required this.session,
    required this.onClose,
    required this.onRetry,
  });

  @override
  State<SessionConnectingView> createState() => _SessionConnectingViewState();
}

class _SessionConnectingViewState extends State<SessionConnectingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _showLogs = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(SessionConnectingView old) {
    super.didUpdateWidget(old);
    _syncAnimation();
  }

  /// Spin only while connecting; freeze for error/disconnected states.
  void _syncAnimation() {
    final connecting = widget.session.status == SessionStatus.connecting;
    if (connecting && !_anim.isAnimating) {
      _anim.repeat();
    } else if (!connecting && _anim.isAnimating) {
      _anim.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Color get _nodeColor => switch (widget.session.status) {
        SessionStatus.error => AppColors.red,
        SessionStatus.disconnected => AppColors.textTertiary,
        _ => AppColors.blue,
      };

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final host = session.host;
    final status = session.status;
    final isError = status == SessionStatus.error;
    final isDisconnected = status == SessionStatus.disconnected;
    final canRetry = isError || isDisconnected;

    final message = switch (status) {
      SessionStatus.error => session.errorMessage ?? 'Connection error',
      SessionStatus.disconnected => 'Disconnected',
      _ => 'Connecting…',
    };
    final messageColor = switch (status) {
      SessionStatus.error => AppColors.red,
      SessionStatus.disconnected => AppColors.textSecondary,
      _ => AppColors.textSecondary,
    };

    // Centered when it fits; scrolls instead of overflowing when the pane is
    // short (split view / small window) — especially with the logs panel open.
    return Container(
      color: AppColors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
              _header(host),
              const SizedBox(height: 22),
              _ConnectionGraphic(
                animation: _anim,
                active: status == SessionStatus.connecting,
                nodeColor: _nodeColor,
              ),
              const SizedBox(height: 14),
              Text(message, style: TextStyle(color: messageColor, fontSize: 12.5)),
              const SizedBox(height: 18),
              Row(
                children: [
                  _PillButton(label: 'Close', onTap: widget.onClose),
                  if (canRetry) ...[
                    const SizedBox(width: 10),
                    _PillButton(
                      label: 'Retry',
                      accent: true,
                      onTap: widget.onRetry,
                    ),
                  ],
                ],
              ),
                        if (_showLogs) ...[
                          const SizedBox(height: 16),
                          _LogsPanel(lines: session.connectionLog),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(Host host) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _OsAvatar(detectedOs: host.detectedOs),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                host.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'SSH ${host.host}:${host.port}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _PillButton(
          label: _showLogs ? 'Hide logs' : 'Show logs',
          onTap: () => setState(() => _showLogs = !_showLogs),
        ),
      ],
    );
  }
}

class _OsAvatar extends StatelessWidget {
  final String? detectedOs;
  const _OsAvatar({required this.detectedOs});

  @override
  Widget build(BuildContext context) {
    final asset = osIconAsset(detectedOs);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: asset != null
          ? SvgPicture.asset(
              asset,
              width: 22,
              height: 22,
              colorFilter:
                  const ColorFilter.mode(AppColors.textPrimary, BlendMode.srcIn),
            )
          : const Icon(Icons.dns_outlined, size: 22, color: AppColors.textPrimary),
    );
  }
}

/// node (link icon, spinning arc while active) ── line ── terminal node.
class _ConnectionGraphic extends StatelessWidget {
  final Animation<double> animation;
  final bool active;
  final Color nodeColor;

  const _ConnectionGraphic({
    required this.animation,
    required this.active,
    required this.nodeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return Row(
            children: [
              _node(
                child: _spinningRing(t),
              ),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, 48),
                  painter: _LinePainter(
                    progress: active ? t : null,
                    color: nodeColor,
                  ),
                ),
              ),
              _node(
                color: AppColors.cardHover,
                child: const Icon(Icons.terminal, size: 20, color: AppColors.textPrimary),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _spinningRing(double t) {
    final icon = const Icon(Icons.link, size: 18, color: Colors.white);
    if (!active) return icon;
    return CustomPaint(
      painter: _ArcPainter(turn: t, color: Colors.white),
      child: SizedBox(width: 38, height: 38, child: Center(child: icon)),
    );
  }

  Widget _node({Color? color, required Widget child}) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color ?? nodeColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double turn;
  final Color color;
  _ArcPainter({required this.turn, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final start = turn * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      math.pi * 0.6,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.turn != turn || old.color != color;
}

class _LinePainter extends CustomPainter {
  /// Animation phase in [0,1] while connecting; null when frozen.
  final double? progress;
  final Color color;
  _LinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final base = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), base);

    if (progress == null) return;
    // A short glowing segment travels left → right along the line.
    final dotX = progress! * size.width;
    final glow = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final half = size.width * 0.12;
    canvas.drawLine(
      Offset((dotX - half).clamp(0, size.width), y),
      Offset((dotX + half).clamp(0, size.width), y),
      glow,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress || old.color != color;
}

class _LogsPanel extends StatelessWidget {
  final List<ConnectionLogLine> lines;
  const _LogsPanel({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: lines.isEmpty
          ? const Text(
              'No logs yet',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12, fontFamily: 'monospace'),
            )
          : SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final l in lines) _line(l)],
              ),
            ),
    );
  }

  Widget _line(ConnectionLogLine l) {
    final color = switch (l.level) {
      ConnectionLogLevel.success => AppColors.accent,
      ConnectionLogLevel.warn => AppColors.orange,
      ConnectionLogLevel.error => AppColors.red,
      ConnectionLogLevel.info => AppColors.textSecondary,
    };
    const base = TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_hms(l.time), style: base.copyWith(color: AppColors.textTertiary)),
          const SizedBox(width: 10),
          Expanded(child: Text(l.message, style: base.copyWith(color: color))),
        ],
      ),
    );
  }

  String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _PillButton extends StatefulWidget {
  final String label;
  final bool accent;
  final VoidCallback onTap;
  const _PillButton({required this.label, this.accent = false, required this.onTap});

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final bg = accent
        ? (_hovered ? AppColors.accentDim : AppColors.accent)
        : (_hovered ? AppColors.cardHover : AppColors.bg);
    final fg = accent ? Colors.black : AppColors.textPrimary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            widget.label,
            style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
