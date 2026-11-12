import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/vnc_session.dart';
import 'package:yourssh/widgets/remote_workspace_chrome.dart';
import 'package:yourssh/widgets/vnc_workspace.dart';
import 'package:yourssh_vnc/yourssh_vnc.dart' show VncClient, VncConfig;
// ignore: implementation_imports
import 'package:yourssh_vnc/src/generated/api.dart' as frb;

import '../helpers/ys_test_app.dart';

Host _host() => Host(
  id: 'v1',
  label: 'desktop',
  host: '10.0.0.5',
  port: 5900,
  username: 'u',
  protocol: HostProtocol.vnc,
);

VncClient _client() => VncClient(
  VncConfig(
    targetHost: '10.0.0.5',
    targetPort: 5900,
    username: 'u',
    password: '',
  ),
);

void main() {
  testWidgets('fullscreen button fires onFullscreenChanged when connected', (
    tester,
  ) async {
    final events = StreamController<frb.VncEvent>();
    final session = VncSession(host: _host(), client: _client());
    session.attach(events.stream);
    var fs = false;
    await tester.pumpWidget(
      ysTestApp(
        VncWorkspace(session: session, onFullscreenChanged: (v) => fs = v),
      ),
    );
    events.add(const frb.VncEvent.connected(width: 800, height: 600));
    await tester.pump();
    await tester.tap(find.byTooltip('Fullscreen'));
    // forui buttons keep a short tap-feedback timer.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(fs, isTrue);
    await events.close();
  });

  testWidgets('shows connecting overlay, then error overlay with retry', (
    tester,
  ) async {
    final events = StreamController<frb.VncEvent>();
    final session = VncSession(host: _host(), client: _client());
    session.attach(events.stream);
    var retried = false;

    await tester.pumpWidget(
      ysTestApp(
        VncWorkspace(session: session, onReconnect: () => retried = true),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(RemoteStatusOverlay),
        matching: find.textContaining('Connecting'),
      ),
      findsOneWidget,
    );

    events.add(const frb.VncEvent.error(message: 'connection refused'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(RemoteStatusOverlay),
        matching: find.textContaining('connection refused'),
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    // forui buttons keep a short tap-feedback timer.
    await tester.pump(const Duration(milliseconds: 200));
    expect(retried, isTrue);
    await events.close();
  });
}
