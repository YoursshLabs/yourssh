import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/services/host_reachability_probe.dart';

void main() {
  test('online reports ms from injected clock', () async {
    var t = DateTime(2026, 1, 1);
    DateTime clock() => t;
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

  test('probeAll debounce — duplicate id is not probed twice concurrently',
      () async {
    var callCount = 0;
    final completer = Future<void>.delayed(const Duration(milliseconds: 10));

    final probe = HostReachabilityProbe(
      connector: (h, p, to) async {
        callCount++;
        await completer;
      },
    );

    // Call probeAll twice with the same host id before the first completes.
    probe.probeAll([
      (id: 'h1', host: '10.0.0.1', port: 22),
    ]);
    probe.probeAll([
      (id: 'h1', host: '10.0.0.1', port: 22),
    ]);

    // Wait for the in-flight probe to finish.
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Despite two probeAll calls the connector must have fired exactly once.
    expect(callCount, 1);
  });
}
