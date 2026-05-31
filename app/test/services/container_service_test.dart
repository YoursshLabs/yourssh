import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/container_entry.dart';
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
}
