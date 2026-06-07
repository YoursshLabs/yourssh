import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart';
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

import '../services/rdp_tunnel_proxy.dart';
import 'app_session.dart';
import 'host.dart';

enum RdpSessionStatus { connecting, connected, disconnected, error }

/// One RDP tab. Holds the event subscription, framebuffer, and status.
/// Pure model: no widget imports; UI listens via [ChangeNotifier].
class RdpSession extends ChangeNotifier implements AppSession {
  RdpSession({
    required this.host,
    required this.client,
    required int width,
    required int height,
    this.tunnelProxy,
  })  : _width = width,
        _height = height,
        framebuffer = Uint8List(width * height * 4);

  final Host host;
  final RdpClient client;

  /// Desktop size. Starts as the requested size; replaced by the
  /// server-negotiated size from the Connected event (servers may override
  /// the request — frame coordinates arrive in the negotiated space).
  int get width => _width;
  int get height => _height;
  int _width;
  int _height;

  Uint8List framebuffer;

  /// Non-null when this session runs through an SSH tunnel; owned by the
  /// session and stopped on [close].
  final RdpTunnelProxy? tunnelProxy;

  @override
  String get id => _id;
  final String _id = 'rdp_${DateTime.now().microsecondsSinceEpoch}';

  RdpSessionStatus status = RdpSessionStatus.connecting;
  String? lastMessage;
  String? certFingerprint;
  bool _tunnelClosed = false;
  bool _closed = false;

  /// Latest decoded frame for painting; rebuilt lazily after patches.
  ui.Image? image;
  bool _decodeInFlight = false;
  bool _dirtyAgain = false;
  StreamSubscription<frb.RdpEvent>? _sub;

  void Function(String text)? onRemoteClipboardText;

  /// Set by [SessionProvider.connectRdp] to gate the Connected event on a
  /// TOFU certificate check. Returns false to reject (triggers disconnect).
  Future<bool> Function(String fingerprint)? certCheckCallback;

  /// Fired when the server's certificate no longer matches the pinned
  /// fingerprint. The connection was aborted BEFORE credentials were sent;
  /// the handler can offer re-trust + reconnect.
  void Function(String fingerprint)? onCertMismatch;

  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned = false;
  @override
  String get tabLabel => customLabel ?? host.label;

  void attach(Stream<frb.RdpEvent> events) {
    _sub = events.listen(_onEvent, onError: (Object e) {
      status = RdpSessionStatus.error;
      lastMessage = '$e';
      notifyListeners();
    });
  }

  /// Called by the tunnel proxy when the SSH side collapsed, so the
  /// disconnect message names the real cause (spec: "SSH tunnel closed").
  void markTunnelClosed() => _tunnelClosed = true;

  void _onEvent(frb.RdpEvent ev) {
    switch (ev) {
      case frb.RdpEvent_Started():
        return; // id captured inside RdpClient.connect
      case frb.RdpEvent_Connected(
          :final cert,
          :final desktopWidth,
          :final desktopHeight
        ):
        certFingerprint = cert.sha256Fingerprint;
        _applyDesktopSize(desktopWidth, desktopHeight);
        final fp = certFingerprint;
        final cb = certCheckCallback;
        if (cb != null && fp != null && fp.isNotEmpty) {
          scheduleMicrotask(() async {
            final ok = await cb(fp);
            // The dialog can stay open for minutes — the session may have
            // disconnected, errored, or been closed in the meantime. Never
            // overwrite a terminal status back to connected.
            if (_closed || status != RdpSessionStatus.connecting) return;
            if (ok) {
              status = RdpSessionStatus.connected;
            } else {
              status = RdpSessionStatus.error;
              lastMessage = 'Certificate rejected';
              unawaited(client.disconnect());
            }
            notifyListeners();
          });
          return; // notifyListeners called inside scheduleMicrotask
        }
        status = RdpSessionStatus.connected;
      case frb.RdpEvent_CertMismatch(:final fingerprint):
        certFingerprint = fingerprint;
        status = RdpSessionStatus.error;
        lastMessage = 'Server certificate changed — connection aborted '
            'before authentication';
        onCertMismatch?.call(fingerprint);
      case frb.RdpEvent_FrameUpdate(
          :final x,
          :final y,
          :final width,
          :final height,
          :final rgba
        ):
        _patch(x, y, width, height, rgba);
      case frb.RdpEvent_ClipboardText(:final text):
        onRemoteClipboardText?.call(text);
        return; // no repaint needed
      case frb.RdpEvent_Disconnected(:final reason):
        status = RdpSessionStatus.disconnected;
        lastMessage = _tunnelClosed ? 'SSH tunnel closed' : reason;
      case frb.RdpEvent_Error(:final message):
        status = RdpSessionStatus.error;
        lastMessage = _tunnelClosed ? 'SSH tunnel closed' : message;
    }
    notifyListeners();
  }

  void _applyDesktopSize(int w, int h) {
    if (w == _width && h == _height) return;
    _width = w;
    _height = h;
    framebuffer = Uint8List(w * h * 4);
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
      // A wedged transport can stall the graceful disconnect indefinitely —
      // never let that block tunnel teardown below.
      await client.disconnect().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Rust side will die with the tunnel/process; nothing more to do.
    } finally {
      client.dispose();
      await tunnelProxy?.stop();
      image?.dispose();
      image = null;
    }
  }
}
