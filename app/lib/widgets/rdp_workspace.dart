import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rdp_session.dart';
import '../services/hotkey_service.dart';
import '../theme/app_theme.dart';
import '../util/rdp_input_mapping.dart';

/// Full workspace for an active RDP tab: rendered remote screen,
/// input capture, slim toolbar, and status overlays.
///
/// In fullscreen ([isFullscreen]) the toolbar is replaced by an auto-hiding
/// pill revealed by hovering the top screen edge (mstsc-style); the widget
/// reports enter/exit intents via [onFullscreenChanged] — the caller owns the
/// actual window state (and hiding the app chrome around this widget).
class RdpWorkspace extends StatefulWidget {
  const RdpWorkspace({
    super.key,
    required this.session,
    this.onReconnect,
    this.isFullscreen = false,
    this.onFullscreenChanged,
  });

  final RdpSession session;
  final VoidCallback? onReconnect;
  final bool isFullscreen;
  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<RdpWorkspace> createState() => _RdpWorkspaceState();
}

class _RdpWorkspaceState extends State<RdpWorkspace> {
  final _focusNode = FocusNode();
  int _lastButton = 1;
  (int, int)? _lastMousePos;
  String? _lastPushedClipboard;
  RdpSessionStatus? _builtStatus;
  bool _hoverBarVisible = false;
  Timer? _hoverBarTimer;

  RdpSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    // Frame updates repaint through the painter's `repaint:` listenable —
    // only a STATUS change needs a widget rebuild. Listening selectively
    // keeps the toolbar/layout/input tree from being rebuilt 30–60×/s.
    session.addListener(_onSessionChanged);
    if (widget.isFullscreen) _flashHoverBar();
  }

  @override
  void didUpdateWidget(RdpWorkspace old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      old.session.removeListener(_onSessionChanged);
      widget.session.addListener(_onSessionChanged);
      _lastMousePos = null;
      _builtStatus = null;
    }
    // Entering fullscreen: show the pill briefly so the exit affordance is
    // discoverable, then auto-hide until the user hovers the top edge.
    if (widget.isFullscreen && !old.isFullscreen) _flashHoverBar();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // Don't trap the user in a fullscreen error screen with no app chrome —
    // drop back to windowed mode the moment the session leaves connected.
    if (widget.isFullscreen &&
        session.status != RdpSessionStatus.connected &&
        session.status != _builtStatus) {
      widget.onFullscreenChanged?.call(false);
    }
    if (session.status != _builtStatus) setState(() {});
  }

  void _flashHoverBar() {
    setState(() => _hoverBarVisible = true);
    _hoverBarTimer?.cancel();
    _hoverBarTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _hoverBarVisible = false);
    });
  }

  void _showHoverBar() {
    _hoverBarTimer?.cancel();
    if (!_hoverBarVisible) setState(() => _hoverBarVisible = true);
  }

  void _hideHoverBarSoon() {
    _hoverBarTimer?.cancel();
    _hoverBarTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _hoverBarVisible = false);
    });
  }

  @override
  void dispose() {
    _hoverBarTimer?.cancel();
    session.removeListener(_onSessionChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _builtStatus = session.status;
    if (widget.isFullscreen) {
      return Stack(children: [
        Positioned.fill(child: _buildBody()),
        // Invisible reveal strip along the top screen edge.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 8,
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => _showHoverBar(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: _hoverBarVisible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !_hoverBarVisible,
                child: MouseRegion(
                  onEnter: (_) => _showHoverBar(),
                  onExit: (_) => _hideHoverBarSoon(),
                  child: _FullscreenPill(
                    session: session,
                    onExitFullscreen: () =>
                        widget.onFullscreenChanged?.call(false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    }
    return Column(children: [
      _Toolbar(
        session: session,
        onEnterFullscreen: widget.onFullscreenChanged == null
            ? null
            : () => widget.onFullscreenChanged!.call(true),
      ),
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildBody() {
    switch (session.status) {
      case RdpSessionStatus.connecting:
        return const Center(child: Text('Connecting…'));
      case RdpSessionStatus.error:
      case RdpSessionStatus.disconnected:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(session.lastMessage ?? 'Disconnected'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: widget.onReconnect, child: const Text('Retry')),
          ]),
        );
      case RdpSessionStatus.connected:
        return LayoutBuilder(builder: (context, constraints) {
          final scale = math.min(constraints.maxWidth / session.width,
              constraints.maxHeight / session.height);
          final renderW = session.width * scale;
          final renderH = session.height * scale;
          final offX = (constraints.maxWidth - renderW) / 2;
          final offY = (constraints.maxHeight - renderH) / 2;

          (int, int) toSession(Offset local) => sessionPointFor(
              localX: local.dx,
              localY: local.dy,
              renderOffsetX: offX,
              renderOffsetY: offY,
              renderScale: scale,
              sessionWidth: session.width,
              sessionHeight: session.height);

          return Focus(
            focusNode: _focusNode,
            autofocus: true,
            onFocusChange: (gained) async {
              if (!gained) return;
              // Spec: push local clipboard to remote when the view gains
              // focus — but only when it changed, so alt-tabbing doesn't
              // re-run the cliprdr advertise handshake for identical content.
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text;
              if (text != null &&
                  text.isNotEmpty &&
                  text != _lastPushedClipboard) {
                _lastPushedClipboard = text;
                session.client.sendClipboardText(text);
              }
            },
            onKeyEvent: (node, event) {
              // A combo registered as an app hotkey already fired at the
              // HardwareKeyboard layer — swallow it here so it doesn't ALSO
              // type into the remote desktop (same contract as TerminalView).
              if (HotkeyService().shouldSwallowKeyEvent(event)) {
                return KeyEventResult.handled;
              }
              final mapped = rdpScancodeFor(event.physicalKey);
              if (mapped == null) return KeyEventResult.ignored;
              final (code, extended) = mapped;
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                session.client
                    .sendKey(scancode: code, extended: extended, down: true);
              } else if (event is KeyUpEvent) {
                session.client
                    .sendKey(scancode: code, extended: extended, down: false);
              }
              return KeyEventResult.handled;
            },
            child: Listener(
              onPointerHover: (e) => _sendMove(toSession(e.localPosition)),
              onPointerMove: (e) => _sendMove(toSession(e.localPosition)),
              onPointerDown: (e) {
                _focusNode.requestFocus();
                final (x, y) = toSession(e.localPosition);
                _lastMousePos = (x, y);
                // e.buttons includes the new button on down; cache it because
                // PointerUpEvent.buttons no longer contains it.
                session.client.sendMouse(
                    x: x, y: y, button: _button(e.buttons), action: 1);
              },
              onPointerUp: (e) {
                final (x, y) = toSession(e.localPosition);
                _lastMousePos = (x, y);
                session.client
                    .sendMouse(x: x, y: y, button: _lastButton, action: 2);
              },
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  final dy = (-e.scrollDelta.dy).round().clamp(-256, 255);
                  if (dy != 0) session.client.sendWheel(delta: dy);
                  final dx = (-e.scrollDelta.dx).round().clamp(-256, 255);
                  if (dx != 0) {
                    session.client.sendWheel(delta: dx, horizontal: true);
                  }
                }
              },
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _FramePainter(session, offX, offY, scale),
              ),
            ),
          );
        });
    }
  }

  /// RDP only renders the latest pointer position — dedupe identical points
  /// so a 1 kHz mouse doesn't push a thousand FFI calls per second.
  void _sendMove((int, int) pos) {
    if (pos == _lastMousePos) return;
    _lastMousePos = pos;
    session.client.sendMouse(x: pos.$1, y: pos.$2);
  }

  int _button(int buttons) {
    _lastButton = switch (buttons) {
      kSecondaryMouseButton => 2,
      kMiddleMouseButton => 3,
      _ => 1,
    };
    return _lastButton;
  }
}

/// Secure-attention sequence, resolved through the shared scancode table
/// (not hand-written codes) so a mapping fix applies here too.
void _sendCtrlAltDel(RdpSession session) {
  final keys = [
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.delete,
  ];
  final codes = keys.map(rdpScancodeFor).whereType<(int, bool)>().toList();
  if (codes.length != keys.length) return; // table miss — never send half
  for (final (code, extended) in codes) {
    session.client.sendKey(scancode: code, extended: extended, down: true);
  }
  for (final (code, extended) in codes.reversed) {
    session.client.sendKey(scancode: code, extended: extended, down: false);
  }
}

Future<void> _pushClipboard(RdpSession session) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null) {
    session.client.sendClipboardText(data!.text!);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.session, this.onEnterFullscreen});
  final RdpSession session;
  final VoidCallback? onEnterFullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: AppColors.card,
      child: Row(children: [
        const SizedBox(width: 8),
        Text(session.tabLabel, style: Theme.of(context).textTheme.labelMedium),
        const Spacer(),
        IconButton(
          tooltip: 'Send Ctrl+Alt+Del',
          icon: const Icon(Icons.keyboard_command_key, size: 16),
          onPressed: () => _sendCtrlAltDel(session),
        ),
        IconButton(
          tooltip: 'Push clipboard to remote',
          icon: const Icon(Icons.content_paste_go, size: 16),
          onPressed: () => _pushClipboard(session),
        ),
        if (onEnterFullscreen != null)
          IconButton(
            tooltip: 'Fullscreen',
            icon: const Icon(Icons.fullscreen, size: 16),
            // Only meaningful with a live desktop behind it.
            onPressed: session.status == RdpSessionStatus.connected
                ? onEnterFullscreen
                : null,
          ),
        IconButton(
          tooltip: 'Disconnect',
          icon: const Icon(Icons.power_settings_new, size: 16),
          onPressed: () => session.client.disconnect(),
        ),
        const SizedBox(width: 4),
      ]),
    );
  }
}

/// mstsc-style floating bar shown in fullscreen: session label + the toolbar
/// actions + exit. Revealed by hovering the top edge; auto-hides.
class _FullscreenPill extends StatelessWidget {
  const _FullscreenPill({
    required this.session,
    required this.onExitFullscreen,
  });

  final RdpSession session;
  final VoidCallback onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(session.tabLabel,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Send Ctrl+Alt+Del',
            icon: const Icon(Icons.keyboard_command_key, size: 16),
            onPressed: () => _sendCtrlAltDel(session),
          ),
          IconButton(
            tooltip: 'Push clipboard to remote',
            icon: const Icon(Icons.content_paste_go, size: 16),
            onPressed: () => _pushClipboard(session),
          ),
          IconButton(
            tooltip: 'Exit fullscreen',
            icon: const Icon(Icons.fullscreen_exit, size: 16),
            onPressed: onExitFullscreen,
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.power_settings_new, size: 16),
            onPressed: () => session.client.disconnect(),
          ),
        ]),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  /// `repaint: session` redraws the canvas on every decoded frame without
  /// rebuilding the surrounding widget tree (the workspace only rebuilds on
  /// status changes).
  _FramePainter(this.session, this.offX, this.offY, this.scale)
      : super(repaint: session);

  final RdpSession session;
  final double offX, offY, scale;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? img = session.image;
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(offX, offY, img.width * scale, img.height * scale),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      !identical(old.session, session) ||
      old.scale != scale ||
      old.offX != offX ||
      old.offY != offY;
}
