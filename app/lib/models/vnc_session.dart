import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yourssh_vnc/yourssh_vnc.dart';
// ignore: implementation_imports
import 'package:yourssh_vnc/src/generated/api.dart' as frb;

import '../services/loopback_tunnel_proxy.dart';
import 'app_session.dart';
import 'host.dart';

enum VncSessionStatus { connecting, connected, disconnected, error }

/// One VNC tab. Mirrors [RdpSession] but with no TLS/cert layer (plain VNC has
/// none — security is the SSH tunnel).
class VncSession extends ChangeNotifier implements AppSession {
  VncSession({required this.host, required this.client, this.tunnelProxy});

  final Host host;
  final VncClient client;

  /// Non-null when this session runs through an SSH tunnel; owned by the
  /// session and stopped on [close].
  final LoopbackTunnelProxy? tunnelProxy;
  bool _tunnelClosed = false;

  /// Desktop size. Starts at 0×0; replaced by the server's framebuffer size
  /// from the Connected event and any later Resize (frame coordinates arrive
  /// in this space).
  int get width => _width;
  int get height => _height;
  int _width = 0;
  int _height = 0;

  Uint8List framebuffer = Uint8List(0);

  @override
  String get id => _id;
  final String _id = 'vnc_${DateTime.now().microsecondsSinceEpoch}';

  VncSessionStatus status = VncSessionStatus.connecting;
  String? lastMessage;
  bool _closed = false;

  /// Called when the remote sends a ServerCutText event. Wire this to the
  /// system clipboard (e.g. [Clipboard.setData]) in the provider.
  void Function(String text)? onRemoteClipboardText;

  /// Latest decoded frame for painting; rebuilt lazily after patches.
  ui.Image? image;
  bool _decodeInFlight = false;
  bool _dirtyAgain = false;
  StreamSubscription<frb.VncEvent>? _sub;

  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned = false;
  @override
  String get tabLabel => customLabel ?? host.label;

  /// Called by the tunnel proxy when the SSH side collapsed, so the
  /// disconnect message names the real cause.
  void markTunnelClosed() => _tunnelClosed = true;

  void attach(Stream<frb.VncEvent> events) {
    _sub = events.listen(_onEvent, onError: (Object e) {
      status = VncSessionStatus.error;
      lastMessage = '$e';
      notifyListeners();
    });
  }

  void _onEvent(frb.VncEvent ev) {
    switch (ev) {
      case frb.VncEvent_Started():
        return; // id captured inside VncClient.connect
      case frb.VncEvent_Connected(:final width, :final height):
        if (!_applyDesktopSize(width, height)) {
          unawaited(client.disconnect());
          notifyListeners();
          return;
        }
        status = VncSessionStatus.connected;
      case frb.VncEvent_Resize(:final width, :final height):
        if (!_applyDesktopSize(width, height)) {
          unawaited(client.disconnect());
          notifyListeners();
          return;
        }
      case frb.VncEvent_FrameUpdate(
          :final x,
          :final y,
          :final width,
          :final height,
          :final rgba
        ):
        _patch(x, y, width, height, rgba);
      case frb.VncEvent_ClipboardText(:final text):
        _deliverClipboard(text);
        return; // no repaint needed
      case frb.VncEvent_Bell():
        return; // no visual state change
      case frb.VncEvent_Disconnected(:final reason):
        status = VncSessionStatus.disconnected;
        lastMessage = _tunnelClosed ? 'SSH tunnel closed' : reason;
      case frb.VncEvent_Error(:final message):
        status = VncSessionStatus.error;
        lastMessage = _tunnelClosed ? 'SSH tunnel closed' : message;
    }
    notifyListeners();
  }

  /// Largest remote clipboard text accepted (UTF-8 bytes).
  static const int maxClipboardBytes = 1024 * 1024;

  void _deliverClipboard(String text) {
    if (!host.remoteClipboard) return;
    // Cheap upper bound first: a UTF-16 unit is at most 3 UTF-8 bytes.
    if (text.length > maxClipboardBytes) return;
    if (text.length * 3 > maxClipboardBytes &&
        utf8.encode(text).length > maxClipboardBytes) {
      return;
    }
    onRemoteClipboardText?.call(text);
  }

  /// Largest desktop a server may negotiate (edge and total pixels); the
  /// framebuffer is allocated eagerly, so an unbounded size is a DoS.
  static const int maxDesktopEdge = 8192;

  static bool _desktopSizeOk(int w, int h) =>
      w > 0 &&
      h > 0 &&
      w <= maxDesktopEdge &&
      h <= maxDesktopEdge &&
      w * h <= maxDesktopEdge * maxDesktopEdge;

  /// Returns false (after flagging an error) when the size is rejected.
  bool _applyDesktopSize(int w, int h) {
    if (!_desktopSizeOk(w, h)) {
      status = VncSessionStatus.error;
      lastMessage = 'Server requested an unsupported desktop size ${w}x$h';
      return false;
    }
    if (w == _width && h == _height) return true;
    _width = w;
    _height = h;
    framebuffer = Uint8List(w * h * 4);
    return true;
  }

  void _patch(int x, int y, int w, int h, Uint8List rgba) {
    final fbStride = _width * 4;
    // Defense in depth: Rust clamps regions to the negotiated size, but a
    // malformed event must never crash the stream listener.
    if (x + w > _width || y + h > _height || rgba.length < w * h * 4) return;
    for (var row = 0; row < h; row++) {
      final dst = (y + row) * fbStride + x * 4;
      final src = row * w * 4;
      framebuffer.setRange(dst, dst + w * 4, rgba, src);
    }
    _scheduleDecode();
  }

  void _scheduleDecode() {
    // One decode at a time, latest-wins: patches landing while a decode is
    // running set a flag and a single follow-up decode picks them all up.
    if (_decodeInFlight) {
      _dirtyAgain = true;
      return;
    }
    _decodeInFlight = true;
    scheduleMicrotask(_decodeLoop);
  }

  Future<void> _decodeLoop() async {
    do {
      _dirtyAgain = false;
      // fromUint8List snapshots synchronously, so the decoded image is
      // internally consistent even if a patch lands during the await.
      final buf = await ui.ImmutableBuffer.fromUint8List(framebuffer);
      final desc = ui.ImageDescriptor.raw(buf,
          width: _width, height: _height, pixelFormat: ui.PixelFormat.rgba8888);
      final codec = await desc.instantiateCodec();
      final decoded = (await codec.getNextFrame()).image;
      if (_closed) {
        decoded.dispose();
        break;
      }
      image?.dispose();
      image = decoded;
      notifyListeners();
    } while (_dirtyAgain);
    _decodeInFlight = false;
  }

  Future<void> close() async {
    _closed = true;
    await _sub?.cancel();
    try {
      // A wedged transport can stall the graceful disconnect indefinitely.
      await client.disconnect().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Rust side will die with the process; nothing more to do.
    } finally {
      client.dispose();
      await tunnelProxy?.stop();
      image?.dispose();
      image = null;
    }
  }
}
