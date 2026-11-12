import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/models/vnc_session.dart';
import 'package:yourssh/widgets/rdp_workspace.dart';
import 'package:yourssh/widgets/terminal_status_bar.dart';
import 'package:yourssh/widgets/vnc_workspace.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient, RdpConfig;
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as rdpApi;
import 'package:yourssh_ui/yourssh_ui.dart' show YsStatusBar;
import 'package:yourssh_vnc/yourssh_vnc.dart' show VncClient, VncConfig;
// ignore: implementation_imports
import 'package:yourssh_vnc/src/generated/api.dart' as vncApi;

import '../helpers/ys_test_app.dart';

class _SpyRdpClient extends RdpClient {
  _SpyRdpClient()
    : super(
        RdpConfig(
          targetHost: 'x',
          targetPort: 3389,
          username: 'u',
          password: '',
          domain: null,
          width: 800,
          height: 600,
          security: 'auto',
        ),
      );
  final moves = <(int, int)>[];
  final keys = <int>[]; // scancodes of key-down events
  final clips = <String>[];
  int disconnects = 0;
  @override
  void sendKey({
    required int scancode,
    required bool extended,
    required bool down,
  }) {
    if (down) keys.add(scancode);
  }

  @override
  void sendClipboardText(String text) => clips.add(text);

  @override
  Future<void> disconnect() async => disconnects++;

  @override
  void sendMouse({
    required int x,
    required int y,
    int button = 0,
    int action = 0,
  }) => moves.add((x, y));
}

class _SpyVncClient extends VncClient {
  _SpyVncClient()
    : super(
        VncConfig(
          targetHost: 'x',
          targetPort: 5900,
          username: 'u',
          password: '',
        ),
      );
  final points = <(int, int)>[];
  final keys = <int>[]; // keysyms of key-down events
  final clips = <String>[];
  int disconnects = 0;
  @override
  void sendKey({required int keysym, required bool down}) {
    if (down) keys.add(keysym);
  }

  @override
  void sendClipboardText(String text) => clips.add(text);

  @override
  Future<void> disconnect() async => disconnects++;

  @override
  void sendPointer({required int x, required int y, required int buttonMask}) =>
      points.add((x, y));
}

Host _host(String label, HostProtocol p) => Host(
  id: 'h',
  label: label,
  host: 'x',
  port: 1,
  username: 'u',
  authType: AuthType.password,
  protocol: p,
);

RdpSession _rdp({String label = 'w', RdpClient? client}) => RdpSession(
  host: _host(label, HostProtocol.rdp),
  client: client ?? _SpyRdpClient(),
  width: 800,
  height: 600,
);

VncSession _vnc({String label = 'v', VncClient? client}) => VncSession(
  host: _host(label, HostProtocol.vnc),
  client: client ?? _SpyVncClient(),
);

const _rdpConnected = rdpApi.RdpEvent.connected(
  cert: rdpApi.RdpCertInfo(sha256Fingerprint: '', subject: 's'),
  desktopWidth: 800,
  desktopHeight: 600,
);
const _vncConnected = vncApi.VncEvent.connected(width: 800, height: 600);

Rect _canvasRect(WidgetTester tester, Type workspace) => tester.getRect(
  find
      .descendant(
        of: find.byType(workspace),
        matching: find.byType(CustomPaint),
      )
      .last,
);

(int, int) _expected(Rect canvas, Offset global) {
  final scale = math.min(canvas.width / 800, canvas.height / 600);
  final offX = (canvas.width - 800 * scale) / 2;
  final offY = (canvas.height - 600 * scale) / 2;
  final l = global - canvas.topLeft;
  return (
    ((l.dx - offX) / scale).round().clamp(0, 799),
    ((l.dy - offY) / scale).round().clamp(0, 599),
  );
}

void main() {
  group('RDP workspace chrome', () {
    testWidgets('status bar mounted below the canvas, hidden in fullscreen', (
      tester,
    ) async {
      final events = StreamController<rdpApi.RdpEvent>();
      final s = _rdp()..attach(events.stream);
      await tester.pumpWidget(ysTestApp(RdpWorkspace(session: s)));
      events.add(_rdpConnected);
      await tester.pump();
      expect(find.byType(SessionStatusBar), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(YsStatusBar)).dy,
        tester.getBottomLeft(find.byType(RdpWorkspace)).dy,
      );

      await tester.pumpWidget(
        ysTestApp(RdpWorkspace(session: s, isFullscreen: true)),
      );
      expect(find.byType(SessionStatusBar), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('frames do not rebuild the status bar', (tester) async {
      final events = StreamController<rdpApi.RdpEvent>();
      final s = _rdp()..attach(events.stream);
      await tester.pumpWidget(ysTestApp(RdpWorkspace(session: s)));
      events.add(_rdpConnected);
      await tester.pump();
      Future<void> frame() async {
        events.add(
          rdpApi.RdpEvent.frameUpdate(
            x: 0,
            y: 0,
            width: 2,
            height: 2,
            rgba: Uint8List(16),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }

      await frame(); // first picture is a state change
      expect(s.image, isNotNull);
      final builds = SessionStatusBar.debugBuildCount;
      expect(builds, greaterThan(0));
      for (var i = 0; i < 20; i++) {
        await frame();
      }
      expect(SessionStatusBar.debugBuildCount, builds);
    });

    testWidgets('click maps to the framebuffer with the bar mounted', (
      tester,
    ) async {
      final spy = _SpyRdpClient();
      final events = StreamController<rdpApi.RdpEvent>();
      final s = _rdp(client: spy)..attach(events.stream);
      await tester.pumpWidget(ysTestApp(RdpWorkspace(session: s)));
      events.add(_rdpConnected);
      await tester.pump();
      final canvas = _canvasRect(tester, RdpWorkspace);
      // Chrome (toolbar + status bar) shortened the canvas.
      expect(canvas.height, lessThan(600 - YsStatusBar.height));
      final p =
          canvas.topLeft + Offset(canvas.width * 0.7, canvas.height * 0.2);
      spy.moves.clear();
      await tester.tapAt(p);
      expect(spy.moves, isNotEmpty);
      expect(spy.moves.last, _expected(canvas, p));
    });

    testWidgets('900x600 with a 60-char label does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final events = StreamController<rdpApi.RdpEvent>();
      final s = _rdp(label: 'r' * 60)..attach(events.stream);
      await tester.pumpWidget(
        ysTestApp(RdpWorkspace(session: s, onFullscreenChanged: (_) {})),
      );
      events.add(_rdpConnected);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('VNC workspace chrome', () {
    testWidgets('status bar mounted below the canvas, hidden in fullscreen', (
      tester,
    ) async {
      final events = StreamController<vncApi.VncEvent>();
      final s = _vnc()..attach(events.stream);
      await tester.pumpWidget(ysTestApp(VncWorkspace(session: s)));
      events.add(_vncConnected);
      await tester.pump();
      expect(find.byType(SessionStatusBar), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(YsStatusBar)).dy,
        tester.getBottomLeft(find.byType(VncWorkspace)).dy,
      );

      await tester.pumpWidget(
        ysTestApp(VncWorkspace(session: s, isFullscreen: true)),
      );
      expect(find.byType(SessionStatusBar), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('frames do not rebuild the status bar', (tester) async {
      final events = StreamController<vncApi.VncEvent>();
      final s = _vnc()..attach(events.stream);
      await tester.pumpWidget(ysTestApp(VncWorkspace(session: s)));
      events.add(_vncConnected);
      await tester.pump();
      Future<void> frame() async {
        events.add(
          vncApi.VncEvent.frameUpdate(
            x: 0,
            y: 0,
            width: 2,
            height: 2,
            rgba: Uint8List(16),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }

      await frame();
      expect(s.image, isNotNull);
      final builds = SessionStatusBar.debugBuildCount;
      expect(builds, greaterThan(0));
      for (var i = 0; i < 20; i++) {
        await frame();
      }
      expect(SessionStatusBar.debugBuildCount, builds);
    });

    testWidgets('click maps to the framebuffer with the bar mounted', (
      tester,
    ) async {
      final spy = _SpyVncClient();
      final events = StreamController<vncApi.VncEvent>();
      final s = _vnc(client: spy)..attach(events.stream);
      await tester.pumpWidget(ysTestApp(VncWorkspace(session: s)));
      events.add(_vncConnected);
      await tester.pump();
      final canvas = _canvasRect(tester, VncWorkspace);
      expect(canvas.height, lessThan(600 - YsStatusBar.height));
      final p =
          canvas.topLeft + Offset(canvas.width * 0.7, canvas.height * 0.2);
      spy.points.clear();
      await tester.tapAt(p);
      expect(spy.points, isNotEmpty);
      expect(spy.points.last, _expected(canvas, p));
    });

    testWidgets('900x600 with a 60-char label does not overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final events = StreamController<vncApi.VncEvent>();
      final s = _vnc(label: 'v' * 60)..attach(events.stream);
      await tester.pumpWidget(
        ysTestApp(VncWorkspace(session: s, onFullscreenChanged: (_) {})),
      );
      events.add(_vncConnected);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('toolbar and pill keep keyboard focus on the canvas', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return {'text': 'clip'};
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    bool canvasHasFocus(WidgetTester tester, Type workspace) => Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byType(workspace),
              matching: find.byType(CustomPaint),
            )
            .last,
      ),
    ).hasPrimaryFocus;

    for (final fullscreen in [false, true]) {
      final where = fullscreen ? 'pill' : 'toolbar';

      testWidgets('RDP $where: Push clipboard / Ctrl+Alt+Del, then typing '
          'still reaches the canvas', (tester) async {
        final spy = _SpyRdpClient();
        final events = StreamController<rdpApi.RdpEvent>();
        final s = _rdp(client: spy)..attach(events.stream);
        await tester.pumpWidget(
          ysTestApp(RdpWorkspace(session: s, isFullscreen: fullscreen)),
        );
        events.add(_rdpConnected);
        await tester.pump();
        await tester.pump();
        expect(canvasHasFocus(tester, RdpWorkspace), isTrue);

        for (final tip in ['Push clipboard to remote', 'Send Ctrl+Alt+Del']) {
          final clipsPre = spy.clips.length;
          spy.keys.clear();
          await tester.tap(find.byTooltip(tip));
          await tester.pump(const Duration(milliseconds: 200));
          // The tap really activated the button (not a vacuous test).
          if (tip.startsWith('Push')) {
            expect(spy.clips.length, clipsPre + 1);
          } else {
            expect(spy.keys.length, 3);
          }
          final clipsBefore = spy.clips.length;
          spy.keys.clear();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(
            canvasHasFocus(tester, RdpWorkspace),
            isTrue,
            reason: 'after $tip',
          );
          expect(spy.keys, [0x1E, 0x39, 0x1C], reason: 'after $tip');
          expect(spy.clips.length, clipsBefore, reason: 'button re-fired');
          expect(spy.disconnects, 0);
        }
        await tester.pump(const Duration(seconds: 3));
      });

      testWidgets('VNC $where: Push clipboard, then typing still reaches '
          'the canvas', (tester) async {
        final spy = _SpyVncClient();
        final events = StreamController<vncApi.VncEvent>();
        final s = _vnc(client: spy)..attach(events.stream);
        await tester.pumpWidget(
          ysTestApp(VncWorkspace(session: s, isFullscreen: fullscreen)),
        );
        events.add(_vncConnected);
        await tester.pump();
        await tester.pump();
        expect(canvasHasFocus(tester, VncWorkspace), isTrue);

        final clipsPre = spy.clips.length;
        await tester.tap(find.byTooltip('Push clipboard to remote'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(spy.clips.length, clipsPre + 1); // the tap activated it
        final clipsBefore = spy.clips.length;
        spy.keys.clear();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(canvasHasFocus(tester, VncWorkspace), isTrue);
        expect(spy.keys, [0x61, 0x20, 0xff0d]);
        expect(spy.clips.length, clipsBefore, reason: 'button re-fired');
        expect(spy.disconnects, 0);
        await tester.pump(const Duration(seconds: 3));
      });
    }
  });
}
