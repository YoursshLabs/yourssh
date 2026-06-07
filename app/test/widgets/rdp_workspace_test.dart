import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/widgets/rdp_workspace.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient, RdpConfig;
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

RdpClient _client() => RdpClient(RdpConfig(
    targetHost: 'x',
    targetPort: 3389,
    username: 'u',
    password: '',
    domain: null,
    width: 800,
    height: 600,
    security: 'auto'));

RdpSession _session() => RdpSession(
    host: Host(
        id: 'h',
        label: 'w',
        host: 'x',
        port: 3389,
        username: 'u',
        authType: AuthType.password,
        protocol: HostProtocol.rdp),
    client: _client(),
    width: 800,
    height: 600);

void main() {
  testWidgets('shows connecting overlay, then error overlay with retry',
      (tester) async {
    final events = StreamController<frb.RdpEvent>();
    final session = _session();
    session.attach(events.stream);

    await tester.pumpWidget(MaterialApp(home: RdpWorkspace(session: session)));
    expect(find.textContaining('Connecting'), findsOneWidget);

    events.add(const frb.RdpEvent.error(message: 'auth failed'));
    await tester.pump();
    expect(find.textContaining('auth failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('toolbar fullscreen button fires onFullscreenChanged(true) '
      'and is only enabled while connected', (tester) async {
    final events = StreamController<frb.RdpEvent>();
    final session = _session();
    session.attach(events.stream);
    bool? changed;

    await tester.pumpWidget(MaterialApp(
        home: RdpWorkspace(
            session: session, onFullscreenChanged: (v) => changed = v)));

    // Still connecting — button rendered but disabled.
    final btn = find.byTooltip('Fullscreen');
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    expect(changed, isNull);

    events.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: '', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    await tester.pump();

    await tester.tap(find.byTooltip('Fullscreen'));
    expect(changed, isTrue);
  });

  testWidgets('no fullscreen button without an onFullscreenChanged handler',
      (tester) async {
    final session = _session();
    await tester.pumpWidget(MaterialApp(home: RdpWorkspace(session: session)));
    expect(find.byTooltip('Fullscreen'), findsNothing);
  });

  testWidgets('fullscreen hides the toolbar; pill exit fires false',
      (tester) async {
    final events = StreamController<frb.RdpEvent>();
    final session = _session();
    session.attach(events.stream);

    bool? changed;
    await tester.pumpWidget(MaterialApp(
        home: RdpWorkspace(
            session: session,
            isFullscreen: true,
            onFullscreenChanged: (v) => changed = v)));
    events.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: '', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    await tester.pump();

    // Toolbar gone, pill present (flashed visible on entering fullscreen).
    expect(find.byTooltip('Fullscreen'), findsNothing);
    final exit = find.byTooltip('Exit fullscreen');
    expect(exit, findsOneWidget);

    await tester.tap(exit);
    expect(changed, isFalse);

    // Pill auto-hides after the flash window.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('leaving connected while fullscreen requests windowed mode',
      (tester) async {
    final events = StreamController<frb.RdpEvent>();
    final session = _session();
    session.attach(events.stream);

    bool? changed;
    await tester.pumpWidget(MaterialApp(
        home: RdpWorkspace(
            session: session,
            isFullscreen: true,
            onFullscreenChanged: (v) => changed = v)));
    events.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: '', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    await tester.pump();
    expect(changed, isNull); // entering connected must not toggle anything

    events.add(const frb.RdpEvent.disconnected(reason: 'gone'));
    await tester.pump();
    expect(changed, isFalse);
    await tester.pump(const Duration(seconds: 3)); // drain hover-bar timer
  });
}
