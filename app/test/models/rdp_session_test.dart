import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient, RdpConfig;
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

Host _host() => Host(
    id: 'h1',
    label: 'win',
    host: '1.2.3.4',
    port: 3389,
    username: 'u',
    authType: AuthType.password,
    protocol: HostProtocol.rdp);

RdpClient _client() => RdpClient(RdpConfig(
    targetHost: '1.2.3.4',
    targetPort: 3389,
    username: 'u',
    password: '',
    domain: null,
    width: 800,
    height: 600,
    security: 'auto'));

void main() {
  test('status transitions on events', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: _client(), width: 800, height: 600);
    s.attach(events.stream);
    expect(s.status, RdpSessionStatus.connecting);

    events.add(const frb.RdpEvent.started(sessionId: 1));
    events.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.connected);

    events.add(const frb.RdpEvent.disconnected(reason: 'bye'));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.disconnected);
    expect(s.lastMessage, 'bye');
  });

  test('negotiated desktop size reallocates the framebuffer', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: _client(), width: 800, height: 600);
    s.attach(events.stream);
    expect(s.framebuffer.length, 800 * 600 * 4);

    // Server overrides the requested 800x600 with 1024x768.
    events.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
        desktopWidth: 1024,
        desktopHeight: 768));
    await Future<void>.delayed(Duration.zero);
    expect(s.width, 1024);
    expect(s.height, 768);
    expect(s.framebuffer.length, 1024 * 768 * 4);

    // A frame at negotiated-space coordinates beyond the old size lands fine.
    final px = Uint8List.fromList([1, 2, 3, 255]);
    events.add(frb.RdpEvent.frameUpdate(
        x: 1000, y: 700, width: 1, height: 1, rgba: px));
    await Future<void>.delayed(Duration.zero);
    final offset = (700 * 1024 + 1000) * 4;
    expect(s.framebuffer[offset], 1);
  });

  test('out-of-bounds frame update is dropped, not crashing', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: _client(), width: 8, height: 8);
    s.attach(events.stream);
    events.add(frb.RdpEvent.frameUpdate(
        x: 6, y: 6, width: 4, height: 4, rgba: Uint8List(4 * 4 * 4)));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.connecting); // no error raised
  });

  test('cert mismatch event sets error and fires callback', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: _client(), width: 800, height: 600);
    String? mismatchFp;
    s.onCertMismatch = (fp) => mismatchFp = fp;
    s.attach(events.stream);

    events.add(const frb.RdpEvent.certMismatch(fingerprint: 'new-fp'));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.error);
    expect(s.certFingerprint, 'new-fp');
    expect(mismatchFp, 'new-fp');
    expect(s.lastMessage, contains('before authentication'));
  });

  test('TOFU result cannot overwrite a disconnect that landed meanwhile', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: _client(), width: 800, height: 600);
    final gate = Completer<bool>();
    s.certCheckCallback = (_) => gate.future;
    s.attach(events.stream);

    events.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.connecting); // awaiting the dialog

    // Server drops while the dialog is open.
    events.add(const frb.RdpEvent.disconnected(reason: 'gone'));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.disconnected);

    // User clicks Accept afterwards — must NOT flip back to connected.
    gate.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.disconnected);
  });

  test('frame updates patch the framebuffer', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: _client(), width: 8, height: 8);
    s.attach(events.stream);
    final red = List<int>.filled(4 * 4 * 4, 0);
    for (var i = 0; i < red.length; i += 4) {
      red[i] = 255;
      red[i + 3] = 255;
    }
    events.add(frb.RdpEvent.frameUpdate(
        x: 2, y: 2, width: 4, height: 4, rgba: Uint8List.fromList(red)));
    await Future<void>.delayed(Duration.zero);
    // pixel (2,2) is red in the full framebuffer
    final offset = (2 * 8 + 2) * 4;
    expect(s.framebuffer[offset], 255);
    expect(s.framebuffer[offset + 3], 255);
  });

  test('tab label uses host label', () {
    final s = RdpSession(host: _host(), client: _client(), width: 800, height: 600);
    expect(s.tabLabel, 'win');
    s.customLabel = 'prod';
    expect(s.tabLabel, 'prod');
  });
}
