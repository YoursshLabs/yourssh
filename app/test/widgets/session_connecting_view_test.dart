import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/connection_log.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/widgets/session_connecting_view.dart';

SshSession _session({
  SessionStatus status = SessionStatus.connecting,
  String? error,
}) {
  final s = SshSession(
    host: Host(id: 'h1', label: 'Thang MacBook Pro', host: 'thngs-macbook-pro', port: 22, username: 'thang'),
    status: status,
  );
  s.errorMessage = error;
  return s;
}

Future<void> _pump(
  WidgetTester tester,
  SshSession session, {
  VoidCallback? onClose,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SessionConnectingView(
        session: session,
        onClose: onClose ?? () {},
        onRetry: onRetry ?? () {},
      ),
    ),
  ));
  await tester.pump(); // start the spinner animation; don't settle (it repeats).
}

void main() {
  testWidgets('shows the host label and SSH host:port subtitle', (tester) async {
    await _pump(tester, _session());
    expect(find.text('Thang MacBook Pro'), findsOneWidget);
    expect(find.text('SSH thngs-macbook-pro:22'), findsOneWidget);
  });

  testWidgets('connecting state shows Close but not Retry', (tester) async {
    await _pump(tester, _session(status: SessionStatus.connecting));
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('error state shows the error message and a Retry button', (tester) async {
    await _pump(tester, _session(status: SessionStatus.error, error: 'Auth failed'));
    expect(find.text('Auth failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('Show logs toggles the connection log panel', (tester) async {
    final s = _session()
      ..logConnection(ConnectionLogLevel.info, 'Resolving thngs-macbook-pro')
      ..logConnection(ConnectionLogLevel.success, 'TCP established');
    await _pump(tester, s);

    // Hidden by default.
    expect(find.text('Resolving thngs-macbook-pro'), findsNothing);

    await tester.tap(find.text('Show logs'));
    await tester.pump();

    expect(find.text('Resolving thngs-macbook-pro'), findsOneWidget);
    expect(find.text('TCP established'), findsOneWidget);
  });

  testWidgets('does not overflow on a short pane with logs open', (tester) async {
    tester.view.physicalSize = const Size(420, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _session();
    for (var i = 0; i < 12; i++) {
      s.logConnection(ConnectionLogLevel.info, 'log line number $i');
    }
    await _pump(tester, s);
    await tester.tap(find.text('Show logs'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Close and Retry fire their callbacks', (tester) async {
    var closed = 0, retried = 0;
    await _pump(
      tester,
      _session(status: SessionStatus.error, error: 'x'),
      onClose: () => closed++,
      onRetry: () => retried++,
    );

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Close'));
    await tester.pump();

    expect(retried, 1);
    expect(closed, 1);
  });
}
