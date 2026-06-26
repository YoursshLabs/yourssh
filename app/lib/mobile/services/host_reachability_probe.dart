import 'dart:io';

import 'package:flutter/foundation.dart';

enum HostReachState { unknown, probing, online, offline }

class HostPing {
  const HostPing(this.state, [this.ms]);
  final HostReachState state;
  final int? ms;
}

typedef Connector = Future<void> Function(String host, int port, Duration timeout);

Future<void> _defaultConnector(String host, int port, Duration timeout) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  socket.destroy();
}

class HostReachabilityProbe extends ChangeNotifier {
  HostReachabilityProbe({
    Connector? connector,
    this._timeout = const Duration(seconds: 3),
    DateTime Function()? clock,
  })  : _connector = connector ?? _defaultConnector,
        _clock = clock ?? DateTime.now;

  final Connector _connector;
  final Duration _timeout;
  final DateTime Function() _clock;

  final Map<String, HostPing> _pings = {};
  final Set<String> _inFlight = {};

  HostPing pingFor(String hostId) =>
      _pings[hostId] ?? const HostPing(HostReachState.unknown);

  Future<void> probe(String hostId, String host, int port) async {
    _pings[hostId] = const HostPing(HostReachState.probing);
    notifyListeners();

    final start = _clock();
    try {
      await _connector(host, port, _timeout);
      final end = _clock();
      final ms = end.difference(start).inMilliseconds;
      _pings[hostId] = HostPing(HostReachState.online, ms);
    } catch (_) {
      _pings[hostId] = const HostPing(HostReachState.offline);
    }
    notifyListeners();
  }

  void probeAll(Iterable<({String id, String host, int port})> hosts) {
    for (final h in hosts) {
      if (_inFlight.contains(h.id)) continue;
      _inFlight.add(h.id);
      probe(h.id, h.host, h.port).whenComplete(() => _inFlight.remove(h.id));
    }
  }
}
