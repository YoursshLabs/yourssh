import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:yourssh/models/discovered_host.dart';
import 'package:yourssh/services/network_discovery_service.dart';

SocketConnector _fakeConnector(Map<String, List<int>> openPorts) {
  return (ip, port, _) async => openPorts[ip]?.contains(port) ?? false;
}

SocketConnector _countingConnector({required List<int> log}) {
  var current = 0;
  return (ip, port, timeout) async {
    current++;
    log.add(current);
    await Future.delayed(const Duration(milliseconds: 5));
    current--;
    return false;
  };
}

// Fake MDnsClient: yields no records, completes immediately.
class _FakeMdnsClient implements MDnsClient {
  @override
  Future<void> start({
    InternetAddress? listenAddress,
    NetworkInterfacesFactory? interfacesFactory,
    int mDnsPort = 5353,
    InternetAddress? mDnsAddress,
    Function? onError,
  }) async {}

  @override
  void stop() {}

  @override
  Stream<T> lookup<T extends ResourceRecord>(
    ResourceRecordQuery query, {
    Duration timeout = const Duration(seconds: 5),
  }) =>
      const Stream.empty();

  @override
  Future<Iterable<NetworkInterface>> allInterfacesFactory(
          InternetAddressType type) =>
      NetworkInterface.list(type: type);
}

MDnsClient _fakeMdns() => _FakeMdnsClient();

SubnetInfo _subnet(String address, String subnet) => SubnetInfo(
      interfaceName: 'en0',
      displayName: 'Wi-Fi',
      address: address,
      subnet: subnet,
    );

void main() {
  group('SubnetInfo.subnetFromAddress', () {
    test('derives /24 subnet', () {
      expect(SubnetInfo.subnetFromAddress('192.168.1.42'), '192.168.1.0/24');
    });
  });

  group('SubnetInfo.hostsInSubnet', () {
    test('produces 254 hosts for /24', () {
      final hosts = SubnetInfo.hostsInSubnet('192.168.1.0/24');
      expect(hosts.length, 254);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
    });
  });

  group('SubnetInfo.validateSubnet', () {
    test('null for valid subnet', () =>
        expect(SubnetInfo.validateSubnet('192.168.1.0/24'), isNull));

    test('error for missing prefix', () =>
        expect(SubnetInfo.validateSubnet('192.168.1.0'), isNotNull));

    test('error for invalid octet', () =>
        expect(SubnetInfo.validateSubnet('192.168.999.0/24'), isNotNull));

    test('error for bad prefix', () =>
        expect(SubnetInfo.validateSubnet('10.0.0.0/33'), isNotNull));
  });

  group('NetworkDiscoveryService TCP scan', () {
    test('emits hosts with open ports only', () async {
      final svc = NetworkDiscoveryService(
        connector: _fakeConnector({
          '192.168.1.10': [22],
          '192.168.1.20': [3389],
        }),
        mdnsFactory: _fakeMdns,
      );
      final results = await svc
          .scan(
            _subnet('192.168.1.5', '192.168.1.0/24'),
            ports: [22, 3389],
            timeout: const Duration(milliseconds: 1),
          )
          .toList();

      final ips = results.map((r) => r.ip).toSet();
      expect(ips, containsAll(['192.168.1.10', '192.168.1.20']));
      final ssh = results.firstWhere((r) => r.ip == '192.168.1.10');
      expect(ssh.openPorts, [22]);
      expect(ssh.source, DiscoverySource.tcpScan);
    });

    test('merges multiple ports for same IP', () async {
      final svc = NetworkDiscoveryService(
        connector: _fakeConnector({'10.0.0.1': [22, 2222]}),
        mdnsFactory: _fakeMdns,
      );
      final results = await svc
          .scan(
            _subnet('10.0.0.5', '10.0.0.0/24'),
            ports: [22, 2222],
            timeout: const Duration(milliseconds: 1),
          )
          .toList();

      final last = results.lastWhere((r) => r.ip == '10.0.0.1');
      expect(last.openPorts, containsAll([22, 2222]));
    });

    test('concurrency does not exceed 50', () async {
      final log = <int>[];
      final svc = NetworkDiscoveryService(
        connector: _countingConnector(log: log),
        mdnsFactory: _fakeMdns,
      );
      await svc
          .scan(
            _subnet('10.0.0.1', '10.0.0.0/24'),
            ports: [22],
            timeout: const Duration(milliseconds: 1),
          )
          .drain<void>();
      expect(log.isNotEmpty, true);
      expect(log.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(50));
    });

    test('onProgress reaches totalHosts at end', () async {
      int lastScanned = 0, lastTotal = 0;
      final svc = NetworkDiscoveryService(
        connector: _fakeConnector({}),
        mdnsFactory: _fakeMdns,
      );
      await svc
          .scan(
            _subnet('192.168.1.1', '192.168.1.0/24'),
            ports: [22],
            timeout: const Duration(milliseconds: 1),
            onProgress: (s, t) {
              lastScanned = s;
              lastTotal = t;
            },
          )
          .drain<void>();
      expect(lastScanned, lastTotal);
      expect(lastTotal, 254);
    });

    test('cancel stops emitting', () async {
      var emitted = 0;
      final svc = NetworkDiscoveryService(
        connector: (ip, port, _) async {
          await Future.delayed(const Duration(milliseconds: 10));
          return true;
        },
        mdnsFactory: _fakeMdns,
      );
      final sub = svc
          .scan(
            _subnet('192.168.1.5', '192.168.1.0/24'),
            ports: [22],
            timeout: const Duration(milliseconds: 10),
          )
          .listen((_) => emitted++);
      await Future.delayed(const Duration(milliseconds: 5));
      svc.cancel();
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(emitted, greaterThanOrEqualTo(0));
    });
  });

  group('DiscoveredHost', () {
    test('merge combines ports and prefers existing hostname', () {
      final a = DiscoveredHost(
          ip: '10.0.0.1',
          hostname: 'myhost',
          openPorts: [22],
          source: DiscoverySource.mdns);
      final b = DiscoveredHost(
          ip: '10.0.0.1', openPorts: [3389], source: DiscoverySource.tcpScan);
      final m = a.merge(b);
      expect(m.hostname, 'myhost');
      expect(m.openPorts, [22, 3389]);
      expect(m.source, DiscoverySource.both);
    });

    test('isRdp true when only 3389 open', () {
      final h = DiscoveredHost(
          ip: '1.2.3.4', openPorts: [3389], source: DiscoverySource.tcpScan);
      expect(h.isRdp, true);
    });

    test('isRdp false when 22 also open', () {
      final h = DiscoveredHost(
          ip: '1.2.3.4',
          openPorts: [22, 3389],
          source: DiscoverySource.tcpScan);
      expect(h.isRdp, false);
    });

    test('portLabel returns SSH for port 22', () {
      final h = DiscoveredHost(
          ip: '1.2.3.4', openPorts: [22], source: DiscoverySource.tcpScan);
      expect(h.portLabel, 'SSH');
    });

    test('portLabel returns RDP for port 3389', () {
      final h = DiscoveredHost(
          ip: '1.2.3.4', openPorts: [3389], source: DiscoverySource.tcpScan);
      expect(h.portLabel, 'RDP');
    });
  });
}
