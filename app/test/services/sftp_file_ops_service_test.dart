// app/test/services/sftp_file_ops_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sftp_file_ops_service.dart';

void main() {
  group('chmodWalk', () {
    // Fake tree: /a is a dir containing f1 and sub/, sub contains f2.
    final tree = <String, List<({String name, bool isDirectory})>>{
      '/a': [
        (name: 'f1', isDirectory: false),
        (name: 'sub', isDirectory: true),
      ],
      '/a/sub': [
        (name: 'f2', isDirectory: false),
      ],
    };

    test('non-recursive touches only the entry itself', () async {
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a',
        isDirectory: true,
        recursive: false,
        setMode: (p) async => touched.add(p),
        list: (p) async => tree[p]!,
      );
      expect(touched, ['/a']);
    });

    test('recursive walks the whole subtree depth-first', () async {
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a',
        isDirectory: true,
        recursive: true,
        setMode: (p) async => touched.add(p),
        list: (p) async => tree[p]!,
      );
      expect(touched, ['/a', '/a/f1', '/a/sub', '/a/sub/f2']);
    });

    test('recursive on a file does not list children', () async {
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a/f1',
        isDirectory: false,
        recursive: true,
        setMode: (p) async => touched.add(p),
        list: (p) async => fail('must not list a file'),
      );
      expect(touched, ['/a/f1']);
    });
  });
}
