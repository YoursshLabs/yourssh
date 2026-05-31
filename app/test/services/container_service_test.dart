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
}
