import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/container_entry.dart' show RuntimeAvailability;
import 'package:yourssh/services/container_service.dart';

void main() {
  group('parseDockerPs', () {
    test('parses pipe-delimited docker ps output', () {
      const out =
          'a1b2c3|web|nginx:latest|Up 2 hours\n'
          'd4e5f6|db|postgres:16|Up 5 minutes (healthy)\n';
      final list = ContainerService.parseDockerPs(out);
      expect(list.length, 2);
      expect(list[0].id, 'a1b2c3');
      expect(list[0].name, 'web');
      expect(list[0].image, 'nginx:latest');
      expect(list[0].status, 'Up 2 hours');
      expect(list[1].name, 'db');
    });

    test('ignores blank and malformed lines', () {
      const out = 'a1|web|nginx|Up\n\nbadline\n';
      final list = ContainerService.parseDockerPs(out);
      expect(list.length, 1);
      expect(list.single.id, 'a1');
    });

    test('empty output yields empty list', () {
      expect(ContainerService.parseDockerPs(''), isEmpty);
    });
  });

  group('parsePods', () {
    test('parses single-namespace kubectl get pods', () {
      const out =
          'NAME       READY   STATUS    RESTARTS   AGE\n'
          'web-0      1/1     Running   0          2d\n'
          'db-0       0/1     Pending   0          5m\n';
      final list = ContainerService.parsePods(out, namespace: 'prod');
      expect(list.length, 2);
      expect(list[0].name, 'web-0');
      expect(list[0].namespace, 'prod');
      expect(list[0].ready, '1/1');
      expect(list[0].status, 'Running');
      expect(list[1].status, 'Pending');
    });

    test('parses all-namespaces output (NAMESPACE column first)', () {
      const out =
          'NAMESPACE   NAME    READY   STATUS    RESTARTS   AGE\n'
          'kube-system   coredns   1/1   Running   1   10d\n';
      final list = ContainerService.parsePods(out, allNamespaces: true);
      expect(list.single.namespace, 'kube-system');
      expect(list.single.name, 'coredns');
      expect(list.single.status, 'Running');
    });

    test('empty / header-only output yields empty list', () {
      expect(ContainerService.parsePods('', namespace: 'x'), isEmpty);
      expect(ContainerService.parsePods('NAME READY STATUS', namespace: 'x'), isEmpty);
    });
  });

  group('parseContainerNames', () {
    test('splits whitespace-separated names', () {
      expect(ContainerService.parseContainerNames('app sidecar  \n'),
          ['app', 'sidecar']);
    });
    test('empty output yields empty list', () {
      expect(ContainerService.parseContainerNames('  \n'), isEmpty);
    });
  });

  group('classifyRuntime', () {
    test('missing command -> notInstalled', () {
      expect(
        ContainerService.classifyRuntime(commandExists: false, psExitCode: 127, psStderr: ''),
        RuntimeAvailability.notInstalled,
      );
    });
    test('present + ps ok -> available', () {
      expect(
        ContainerService.classifyRuntime(commandExists: true, psExitCode: 0, psStderr: ''),
        RuntimeAvailability.available,
      );
    });
    test('present + permission denied -> noPermission', () {
      expect(
        ContainerService.classifyRuntime(
            commandExists: true, psExitCode: 1, psStderr: 'permission denied while trying to connect to the Docker daemon socket'),
        RuntimeAvailability.noPermission,
      );
    });
    test('present + other error -> available (let listing surface it)', () {
      expect(
        ContainerService.classifyRuntime(commandExists: true, psExitCode: 1, psStderr: 'Cannot connect: timeout'),
        RuntimeAvailability.available,
      );
    });
  });

  group('installHint', () {
    test('docker on ubuntu suggests get.docker.com', () {
      final h = ContainerService.installHint('docker', 'Ubuntu 22.04');
      expect(h, contains('get.docker.com'));
    });
    test('docker noPermission suggests usermod group', () {
      final h = ContainerService.permissionHint('docker');
      expect(h, contains('usermod -aG docker'));
    });
    test('kubectl hint is non-empty for unknown os', () {
      expect(ContainerService.installHint('kubectl', null), isNotEmpty);
    });
  });

  group('exec commands', () {
    test('docker exec uses bash->sh fallback', () {
      final cmd = ContainerService.dockerExecCommand('abc123');
      expect(cmd, contains('docker exec -it abc123'));
      expect(cmd, contains('exec bash || exec sh'));
    });
    test('kubectl exec includes namespace and container', () {
      final cmd = ContainerService.kubectlExecCommand('web-0', 'prod', 'app');
      expect(cmd, contains('kubectl exec -it web-0'));
      expect(cmd, contains('-n prod'));
      expect(cmd, contains('-c app'));
      expect(cmd, contains('--'));
    });
    test('kubectl exec omits -c when container is null', () {
      final cmd = ContainerService.kubectlExecCommand('web-0', 'prod', null);
      // No kubectl -c <name> flag; note: sh -c in the shell fallback is unrelated.
      expect(cmd, isNot(matches(RegExp(r'-c \w'))));
    });
  });
}
