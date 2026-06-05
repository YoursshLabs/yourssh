// app/test/services/sftp_file_ops_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/sftp_file_ops_service.dart';

void main() {
  group('chmodWalk', () {
    // Fake tree: /a contains f1, a symlink, and sub/; sub contains f2.
    final tree = <String, List<WalkChild>>{
      '/a': [
        (name: 'f1', isDirectory: false, isSymlink: false),
        (name: 'ln', isDirectory: false, isSymlink: true),
        (name: 'sub', isDirectory: true, isSymlink: false),
      ],
      '/a/sub': [
        (name: 'f2', isDirectory: false, isSymlink: false),
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

    test('recursive walks post-order: children before their own directory',
        () async {
      // A restrictive target mode (e.g. 600) must not strip our own r/x on
      // the directory while the walk is still inside it.
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a',
        isDirectory: true,
        recursive: true,
        setMode: (p) async => touched.add(p),
        list: (p) async => tree[p]!,
      );
      expect(touched, ['/a/sub/f2', '/a/sub', '/a/f1', '/a']);
    });

    test('symlink children are never chmodded or recursed', () async {
      // SFTP v3 SETSTAT follows the link — chmod-ing it would alter the
      // target, possibly outside the tree. chmod -R skips them too.
      final touched = <String>[];
      await SftpFileOpsService.chmodWalk(
        path: '/a',
        isDirectory: true,
        recursive: true,
        setMode: (p) async => touched.add(p),
        list: (p) async => tree[p]!,
      );
      expect(touched, isNot(contains('/a/ln')));
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

    test('file children are chmodded concurrently in bounded batches',
        () async {
      final many = <String, List<WalkChild>>{
        '/d': [
          for (var i = 0; i < 20; i++)
            (name: 'f$i', isDirectory: false, isSymlink: false),
        ],
      };
      var inFlight = 0, maxInFlight = 0;
      await SftpFileOpsService.chmodWalk(
        path: '/d',
        isDirectory: true,
        recursive: true,
        setMode: (p) async {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          inFlight--;
        },
        list: (p) async => many[p]!,
      );
      expect(maxInFlight, greaterThan(1)); // actually parallel
      expect(maxInFlight, lessThanOrEqualTo(8)); // but bounded
    });
  });
}
