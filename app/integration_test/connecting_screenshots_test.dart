// Captures screenshots of the SSH connection screen (SessionConnectingView)
// in its connecting and error+logs states. Pumps the widget directly (it takes
// plain callbacks, no providers) so the transient connecting state is
// deterministic, and captures from the render tree — no Screen-Recording
// permission needed.
//
// Run:
//   cd app && flutter test integration_test/connecting_screenshots_test.dart -d macos
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yourssh/models/connection_log.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/session_connecting_view.dart';

const _outDir = '/Users/thangnguyen/Projects/Personal/yourssh/screenshots';
const _g1 = '$_outDir/01-terminal-ssh';

final _captureKey = GlobalKey();

/// Captures exactly the fixed-size RepaintBoundary around the card — independent
/// of the real macOS window size, so the framing is deterministic.
Future<void> _snap(WidgetTester tester, String path) async {
  await tester.pump(const Duration(milliseconds: 200));
  final boundary =
      _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('SNAP: $path');
}

SshSession _session(SessionStatus status, {String? error}) {
  final s = SshSession(
    host: Host(
      id: 'demo',
      label: 'Thang MacBook Pro',
      host: 'thngs-macbook-pro',
      port: 22,
      username: 'thang',
      detectedOs: 'macos',
    ),
    status: status,
  );
  s.errorMessage = error;
  return s;
}

Future<void> _pump(WidgetTester tester, SshSession session) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: RepaintBoundary(
          key: _captureKey,
          child: SizedBox(
            width: 760,
            height: 520,
            child: SessionConnectingView(
              session: session,
              onClose: () {},
              onRetry: () {},
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connecting state', (tester) async {
    final s = _session(SessionStatus.connecting)
      ..logConnection(ConnectionLogLevel.info, 'Connecting to thngs-macbook-pro:22 as thang')
      ..logConnection(ConnectionLogLevel.info, 'Auth method: publicKey');
    await _pump(tester, s);
    await _snap(tester, '$_g1/ssh-connecting.png');
    await tester.pumpWidget(const SizedBox()); // unmount → dispose animation
  });

  testWidgets('error state with logs open', (tester) async {
    final s = _session(SessionStatus.error, error: 'Auth failed: permission denied (publickey)')
      ..logConnection(ConnectionLogLevel.info, 'Connecting to thngs-macbook-pro:22 as thang')
      ..logConnection(ConnectionLogLevel.info, 'Auth method: publicKey')
      ..logConnection(ConnectionLogLevel.info, 'Verifying host key (ssh-ed25519) for thngs-macbook-pro:22')
      ..logConnection(ConnectionLogLevel.success, 'Host key accepted')
      ..logConnection(ConnectionLogLevel.error, 'Connection failed: permission denied (publickey)');
    await _pump(tester, s);
    await tester.tap(find.text('Show logs'));
    await _snap(tester, '$_g1/ssh-connecting-error-logs.png');
    await tester.pumpWidget(const SizedBox());
  });
}
