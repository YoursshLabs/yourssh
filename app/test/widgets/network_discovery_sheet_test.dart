import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/discovered_host.dart';
import 'package:yourssh/services/network_discovery_service.dart';
import 'package:yourssh/widgets/network_discovery_sheet.dart';

import '../helpers/ys_test_app.dart';

class _FakeDiscovery extends NetworkDiscoveryService {
  final List<SubnetInfo> subnets;
  final List<DiscoveredHost> found;
  int scans = 0;
  _FakeDiscovery(this.subnets, this.found);

  @override
  Future<List<SubnetInfo>> getLocalSubnets() async => subnets;

  @override
  Stream<DiscoveredHost> scan(
    SubnetInfo subnet, {
    List<int> ports = const [22],
    Duration timeout = const Duration(milliseconds: 500),
    void Function(int scanned, int total)? onProgress,
  }) {
    scans++;
    onProgress?.call(254, 254);
    return Stream.fromIterable(found);
  }

  @override
  void cancel() {}
}

const _wifi = SubnetInfo(
  interfaceName: 'en0',
  displayName: 'Wi-Fi',
  address: '192.168.1.10',
  subnet: '192.168.1.0/24',
);
const _eth = SubnetInfo(
  interfaceName: 'en1',
  displayName: 'Ethernet',
  address: '10.0.0.10',
  subnet: '10.0.0.0/24',
);

Future<void> _pumpSheet(
  WidgetTester t,
  _FakeDiscovery svc, {
  bool selectionMode = false,
  void Function(DiscoveredHost)? onSelected,
}) async {
  t.view.physicalSize = const Size(900, 600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ysTestApp(Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => NetworkDiscoverySheet.show(
          context,
          selectionMode: selectionMode,
          onSelected: onSelected,
          service: svc,
        ),
        child: const Text('open'),
      ),
    ),
  )));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  final ssh = DiscoveredHost(
    ip: '192.168.1.20',
    hostname: 'nas.local',
    openPorts: const [22],
    source: DiscoverySource.both,
  );
  final rdp = DiscoveredHost(
    ip: '192.168.1.30',
    openPorts: const [3389],
    source: DiscoverySource.tcpScan,
  );

  testWidgets('smoke: header, subnet bar, counters and row actions',
      (t) async {
    final svc = _FakeDiscovery([_wifi, _eth], [ssh, rdp]);
    await _pumpSheet(t, svc);

    expect(find.text('Discover Devices'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    // Interface picker (more than one interface) shows the current one.
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('mDNS: 1 found · TCP scan: 2 found'), findsOneWidget);
    expect(find.text('nas.local'), findsOneWidget);
    expect(find.text('192.168.1.20'), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
    expect(find.text('RDP'), findsOneWidget);
    expect(find.text('Add'), findsNWidgets(2));
    expect(find.text('Connect'), findsNWidgets(2));
    expect(t.takeException(), isNull);

    // Switch interface: the subnet field follows.
    await t.tap(find.text('Wi-Fi'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ethernet'));
    await t.pumpAndSettle();
    expect(find.text('10.0.0.0/24'), findsOneWidget);

    await t.tap(find.text('Scan'));
    await t.pumpAndSettle();
    expect(svc.scans, 2);

    // Invalid subnet disables Scan and shows the error.
    await t.enterText(
        find.descendant(
            of: find.byKey(const Key('discovery-subnet')),
            matching: find.byType(EditableText)),
        'nope');
    await t.pumpAndSettle();
    expect(find.text('Expected format: 192.168.1.0/24'), findsOneWidget);

    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('Discover Devices'), findsNothing);
  });

  testWidgets('selection mode: tapping a row selects and closes', (t) async {
    DiscoveredHost? picked;
    final svc = _FakeDiscovery([_wifi], [ssh]);
    await _pumpSheet(t, svc, selectionMode: true, onSelected: (h) => picked = h);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Connect'), findsNothing);
    await t.tap(find.text('nas.local'));
    await t.pumpAndSettle();
    expect(picked?.ip, '192.168.1.20');
    expect(find.text('Discover Devices'), findsNothing);
  });

  testWidgets('no interfaces message', (t) async {
    await _pumpSheet(t, _FakeDiscovery([], []));
    expect(find.text('No active network interfaces found.'), findsOneWidget);
    expect(find.text('No devices found yet…'), findsOneWidget);
  });
}
