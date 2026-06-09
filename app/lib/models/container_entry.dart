import 'dart:async';
import 'dart:io';

/// One running Docker container (subset of `docker ps`).
class ContainerEntry {
  final String id;
  final String name;
  final String image;
  final String status;

  const ContainerEntry({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
  });
}

/// One Kubernetes pod (subset of `kubectl get pods`).
class PodEntry {
  final String name;
  final String namespace;
  final String ready;
  final String status;
  final List<String> containers;

  const PodEntry({
    required this.name,
    required this.namespace,
    required this.ready,
    required this.status,
    this.containers = const [],
  });
}

enum RuntimeAvailability { available, notInstalled, noPermission }

class RuntimeStatus {
  final RuntimeAvailability docker;
  final RuntimeAvailability kubectl;

  const RuntimeStatus({required this.docker, required this.kubectl});
}

/// Tracks a running `kubectl port-forward` process and the matching local
/// TCP server. Call [stop] to tear both down.
class K8sForwardHandle {
  K8sForwardHandle({
    required this.pod,
    required this.namespace,
    required this.podPort,
    required this.localPort,
    required StreamSubscription<String> kubectlSub,
    required ServerSocket server,
    required StreamSubscription<Socket> serverSub,
    required List<void Function()> closers,
  }) // ignore: prefer_initializing_formals
      : _kubectlSub = kubectlSub, // ignore: prefer_initializing_formals
        _server = server, // ignore: prefer_initializing_formals
        _serverSub = serverSub, // ignore: prefer_initializing_formals
        _closers = closers; // ignore: prefer_initializing_formals

  final String pod;
  final String namespace;
  final int podPort;
  final int localPort;

  final StreamSubscription<String> _kubectlSub;
  final ServerSocket _server;
  final StreamSubscription<Socket> _serverSub;
  final List<void Function()> _closers;

  bool _stopped = false;

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    try {
      await _serverSub.cancel();
    } finally {
      try {
        await _server.close();
      } finally {
        for (final c in List.of(_closers)) {
          c();
        }
        await _kubectlSub.cancel();
      }
    }
  }
}
