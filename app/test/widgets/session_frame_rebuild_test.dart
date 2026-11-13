import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/models/vnc_session.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as rdpfrb;
import 'package:yourssh_vnc/src/generated/api.dart' as frb;

import '../helpers/ys_test_app.dart';

final _vncHost = Host(
  id: 'vnc1',
  label: 'desktop',
  host: '10.0.0.5',
  port: 5900,
  username: 'u',
  protocol: HostProtocol.vnc,
);

final _rdpHost = Host(
  id: 'rdp1',
  label: 'win',
  host: '10.0.0.6',
  port: 3389,
  username: 'u',
  protocol: HostProtocol.rdp,
);

void main() {
  // MainScreen watches SessionProvider at the top of build; a streaming
  // remote desktop must not rebuild it (and the dashboard under it) per frame.
  testWidgets('VNC frames do not rebuild SessionProvider watchers; status '
      'changes still do', (t) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    late HostProvider hosts;
    late SettingsProvider settings;
    late SessionProvider sessions;
    late VncSession vnc;
    final events = StreamController<frb.VncEvent>();
    await t.runAsync(() async {
      hosts = HostProvider(storage);
      await hosts.ready;
      await hosts.addHost(_vncHost);
      settings = SettingsProvider();
      sessions = SessionProvider(SshService(storage), TabMetadataService());
      // No native library under test: the tab opens in error state and the
      // test drives its event stream directly.
      vnc = (await sessions.connectVnc(_vncHost))!;
      vnc.attach(events.stream);
      events.add(const frb.VncEvent.connected(width: 4, height: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(vnc.status, VncSessionStatus.connected);

    var notifications = 0;
    sessions.addListener(() => notifications++);
    var shellBuilds = 0;
    var dashboardBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is HostsDashboard) dashboardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hosts),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ],
      child: ysTestApp(Builder(builder: (context) {
        context.watch<SessionProvider>(); // what MainScreen.build does
        shellBuilds++;
        return const HostsDashboard();
      })),
    ));
    await t.pumpAndSettle();
    final shellBefore = shellBuilds;
    final dashBefore = dashboardBuilds;

    final pixel = Uint8List.fromList([255, 0, 0, 255]);
    for (var i = 0; i < 100; i++) {
      await t.runAsync(() async {
        events.add(frb.VncEvent.frameUpdate(
            x: i % 4, y: 0, width: 1, height: 1, rgba: pixel));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      await t.pump();
    }
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();

    // The first decoded image is a state change (null -> image); every
    // other frame is a repaint only.
    expect(notifications, lessThanOrEqualTo(1));
    expect(shellBuilds - shellBefore, lessThanOrEqualTo(1));
    expect(dashboardBuilds - dashBefore, lessThanOrEqualTo(1));
    expect(vnc.image, isNotNull, reason: 'frames still reach the session');

    // A status change still propagates. Fresh baseline: the first-image
    // notification above must not satisfy this check.
    final shellBeforeStatus = shellBuilds;
    await t.runAsync(() async {
      events.add(const frb.VncEvent.disconnected(reason: 'bye'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
    expect(vnc.status, VncSessionStatus.disconnected);
    expect(shellBuilds - shellBeforeStatus, greaterThanOrEqualTo(1));
    await events.close();
  });

  testWidgets('RDP frames do not rebuild SessionProvider watchers; status '
      'changes still do', (t) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    late HostProvider hosts;
    late SettingsProvider settings;
    late SessionProvider sessions;
    late RdpSession rdp;
    final events = StreamController<rdpfrb.RdpEvent>();
    await t.runAsync(() async {
      hosts = HostProvider(storage);
      await hosts.ready;
      await hosts.addHost(_rdpHost);
      settings = SettingsProvider();
      sessions = SessionProvider(SshService(storage), TabMetadataService());
      // No native library under test: the tab opens in error state and the
      // test drives its event stream directly.
      rdp = (await sessions.connectRdp(_rdpHost))!;
      rdp.attach(events.stream);
      events.add(rdpfrb.RdpEvent.connected(
          cert: const rdpfrb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
          desktopWidth: 4,
          desktopHeight: 2));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(rdp.status, RdpSessionStatus.connected);

    var notifications = 0;
    sessions.addListener(() => notifications++);
    var shellBuilds = 0;
    var dashboardBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is HostsDashboard) dashboardBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hosts),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
      ],
      child: ysTestApp(Builder(builder: (context) {
        context.watch<SessionProvider>(); // what MainScreen.build does
        shellBuilds++;
        return const HostsDashboard();
      })),
    ));
    await t.pumpAndSettle();
    final shellBefore = shellBuilds;
    final dashBefore = dashboardBuilds;

    final pixel = Uint8List.fromList([255, 0, 0, 255]);
    for (var i = 0; i < 100; i++) {
      await t.runAsync(() async {
        events.add(rdpfrb.RdpEvent.frameUpdate(
            x: i % 4, y: 0, width: 1, height: 1, rgba: pixel));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      });
      await t.pump();
    }
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();

    // The first decoded image is a state change (null -> image); every
    // other frame is a repaint only.
    expect(notifications, lessThanOrEqualTo(1));
    expect(shellBuilds - shellBefore, lessThanOrEqualTo(1));
    expect(dashboardBuilds - dashBefore, lessThanOrEqualTo(1));
    expect(rdp.image, isNotNull, reason: 'frames still reach the session');

    // A status change still propagates. Fresh baseline: the first-image
    // notification above must not satisfy this check.
    final shellBeforeStatus = shellBuilds;
    await t.runAsync(() async {
      events.add(const rdpfrb.RdpEvent.disconnected(reason: 'bye'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
    expect(rdp.status, RdpSessionStatus.disconnected);
    expect(shellBuilds - shellBeforeStatus, greaterThanOrEqualTo(1));
    await events.close();
  });
}
