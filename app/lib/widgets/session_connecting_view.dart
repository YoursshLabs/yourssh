import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/connection_log.dart';
import '../models/host.dart';
import '../models/ssh_session.dart';
import '../services/os_detection.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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
        SessionStatus.error => YsColors.error,
        SessionStatus.disconnected => YsColors.off,
        _ => YsColors.primary,
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
      // Between auto-retries the status stays `connecting`; show why the last
      // attempt failed so a bad host name isn't an endless bare "Connecting…".
      _ when session.errorMessage != null =>
        '${session.errorMessage} — retrying (attempt ${session.reconnectCount + 1})',
      _ => 'Connecting…',
    };
    final messageColor = switch (status) {
      SessionStatus.error => YsColors.error,
      SessionStatus.disconnected => YsColors.mutedForeground,
      _ => YsColors.mutedForeground,
    };

    // Centered when it fits; scrolls instead of overflowing when the pane is
    // short (split view / small window) — especially with the logs panel open.
    return ColoredBox(
      color: YsColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(YsSpace.s5),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    decoration: BoxDecoration(
                      color: YsColors.card,
                      borderRadius: BorderRadius.circular(YsRadius.card),
                      border: Border.all(color: YsColors.border),
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
                        Text(
                          message,
                          style: TextStyle(color: messageColor, fontSize: 12.5),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            FButton(
                              key: const Key('connecting-close'),
                              variant: .outline,
                              size: .sm,
                              mainAxisSize: MainAxisSize.min,
                              onPress: widget.onClose,
                              child: const Text('Close'),
                            ),
                            if (canRetry) ...[
                              const SizedBox(width: 10),
                              FButton(
                                key: const Key('connecting-retry'),
                                size: .sm,
                                mainAxisSize: MainAxisSize.min,
                                onPress: widget.onRetry,
                                prefix: const Icon(FLucideIcons.refreshCw),
                                child: const Text('Retry'),
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
                  color: YsColors.foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'SSH ${host.host}:${host.port}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 12,
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Flexible: in a narrow split pane the button shrinks (ellipsis)
        // instead of overflowing the header.
        Flexible(
          flex: 2,
          child: FButton(
            key: const Key('connecting-logs'),
            variant: .ghost,
            size: .sm,
            mainAxisSize: MainAxisSize.min,
            onPress: () => setState(() => _showLogs = !_showLogs),
            prefix: const Icon(FLucideIcons.scrollText),
            child: Flexible(
              child: Text(
                _showLogs ? 'Hide logs' : 'Show logs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
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
        color: YsColors.secondary,
        borderRadius: BorderRadius.circular(YsRadius.card),
      ),
      alignment: Alignment.center,
      child: asset != null
          ? SvgPicture.asset(
              asset,
              width: 22,
              height: 22,
              colorFilter:
                  const ColorFilter.mode(YsColors.foreground, BlendMode.srcIn),
            )
          : const Icon(FLucideIcons.server, size: 22, color: YsColors.foreground),
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
                color: YsColors.secondary,
                child: const Icon(FLucideIcons.terminal,
                    size: 20, color: YsColors.foreground),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _spinningRing(double t) {
    const icon = Icon(FLucideIcons.link, size: 18, color: YsColors.foreground);
    if (!active) return icon;
    return CustomPaint(
      painter: _ArcPainter(turn: t, color: YsColors.foreground),
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
      ..color = YsColors.border
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
        color: YsColors.background,
        borderRadius: BorderRadius.circular(YsRadius.control),
        border: Border.all(color: YsColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: lines.isEmpty
          ? const Text(
              'No logs yet',
              style: TextStyle(
                color: YsColors.off,
                fontSize: 12,
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
              ),
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
      ConnectionLogLevel.success => YsColors.ok,
      ConnectionLogLevel.warn => YsColors.warn,
      ConnectionLogLevel.error => YsColors.error,
      ConnectionLogLevel.info => YsColors.mutedForeground,
    };
    const base = TextStyle(
      fontSize: 12,
      fontFamily: kYsMonoFontFamily,
      fontFamilyFallback: kYsMonoFontFallback,
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_hms(l.time), style: base.copyWith(color: YsColors.off)),
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
