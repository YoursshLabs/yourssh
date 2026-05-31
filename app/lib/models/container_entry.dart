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
