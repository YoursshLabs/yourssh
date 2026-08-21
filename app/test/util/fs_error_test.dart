import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/fs_error.dart';

void main() {
  group('describeFileSystemError', () {
    test('permission denials name the folder and how to grant access', () {
      final message = describeFileSystemError(
        const PathAccessException(
          '/Users/me/Downloads',
          OSError('Operation not permitted', 1),
          'Directory listing failed',
        ),
        path: '/Users/me/Downloads',
      );

      expect(message, contains('Downloads'));
      expect(message, contains('Privacy & Security'));
      expect(message, isNot(contains('errno')));
    });

    test('missing directories read as missing, not as denied', () {
      final message = describeFileSystemError(
        const PathNotFoundException(
          '/Users/me/gone',
          OSError('No such file or directory', 2),
        ),
        path: '/Users/me/gone',
      );

      expect(message, contains('no longer exists'));
      expect(message, isNot(contains('Privacy & Security')));
    });

    test('EACCES is treated as a permission denial too', () {
      final message = describeFileSystemError(
        const FileSystemException(
          'Directory listing failed',
          '/private/root',
          OSError('Permission denied', 13),
        ),
        path: '/private/root',
      );

      expect(message, contains('Privacy & Security'));
    });

    test('unknown errors keep their own text so nothing is swallowed', () {
      final message = describeFileSystemError(
        const FileSystemException('Disk I/O failure', '/x', OSError('io', 5)),
        path: '/x',
      );

      expect(message, contains('Disk I/O failure'));
    });
  });
}
