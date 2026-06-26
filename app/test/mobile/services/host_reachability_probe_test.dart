import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/services/host_reachability_probe.dart';

void main() {
  test('online reports ms from injected clock', () async {
    var t = DateTime(2026, 1, 1);
    final clock = () => t;
    final probe = HostReachabilityProbe(
        connector: (h, p, to) async {
          t = t.add(const Duration(milliseconds: 24));
        },
        clock: clock);
    await probe.probe('h1', '10.0.0.1', 22);
    expect(probe.pingFor('h1').state, HostReachState.online);
    expect(probe.pingFor('h1').ms, 24);
  });

  test('connector throw -> offline, no rethrow', () async {
    final probe = HostReachabilityProbe(
        connector: (h, p, to) async => throw const SocketException('x'));
    await probe.probe('h2', '10.0.0.2', 22);
    expect(probe.pingFor('h2').state, HostReachState.offline);
  });
}
