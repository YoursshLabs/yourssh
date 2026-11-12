import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/ys_test_app.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/vnc_session.dart';
import 'package:yourssh/widgets/remote_workspace_chrome.dart';
import 'package:yourssh/widgets/vnc_workspace.dart';
import 'package:yourssh_vnc/yourssh_vnc.dart' show VncClient, VncConfig;
// ignore: implementation_imports
import 'package:yourssh_vnc/src/generated/api.dart' as frb;

Host _host() => Host(
    id: 'v1',
    label: 'desktop',
    host: '10.0.0.5',
    port: 5900,
    username: 'u',
    protocol: HostProtocol.vnc);

VncClient _client() => VncClient(VncConfig(
    targetHost: '10.0.0.5', targetPort: 5900, username: 'u', password: ''));

void main() {
  testWidgets('connect swaps the status view for an interactive surface',
      (tester) async {
    final events = StreamController<frb.VncEvent>();
    final session = VncSession(host: _host(), client: _client());
    session.attach(events.stream);

    await tester.pumpWidget(ysTestApp(VncWorkspace(session: session)));
    expect(find.descendant(of: find.byType(RemoteStatusOverlay), matching: find.textContaining('Connecting')), findsOneWidget);

    // Move to connected (server framebuffer 800x600); no frame decoded yet.
    events.add(const frb.VncEvent.connected(width: 800, height: 600));
    await tester.pump();

    // The connecting status view is gone, replaced by the interactive surface.
    expect(find.descendant(of: find.byType(RemoteStatusOverlay), matching: find.textContaining('Connecting')), findsNothing);

    // The input surface is owned BY the workspace (scoped to its subtree, so
    // this does NOT match the Listener widgets MaterialApp/Scaffold inject as
    // ancestors — the bug the original assertion missed).
    expect(
      find.descendant(
          of: find.byType(VncWorkspace), matching: find.byType(Listener)),
      findsWidgets,
    );

    // Before the first frame the workspace shows the waiting affordance while
    // staying interactive (regression guard for the M2->M3 rewrite).
    expect(find.descendant(of: find.byType(RemoteStatusOverlay), matching: find.textContaining('Waiting for first frame')), findsOneWidget);

    // A key event reaches the workspace's Focus handler without throwing
    // (sendKey no-ops at the bridge because the client has no live session id).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    await events.close();
  });
}
