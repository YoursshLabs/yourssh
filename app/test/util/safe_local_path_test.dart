import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/safe_local_path.dart';

void main() {
  group('isSafeRemoteEntryName', () {
    for (final bad in [
      '',
      '.',
      '..',
      '../evil',
      '../../.zshrc',
      '/abs/x',
      '/Users/victim/.ssh/authorized_keys',
      'a/..',
      'a/b',
      '..\\x',
      'C:\\x',
      'x\u0000y',
      'x\ny',
      'x\u007fy',
    ]) {
      test('rejects ${bad.codeUnits}', () {
        expect(isSafeRemoteEntryName(bad), isFalse);
      });
    }

    for (final ok in ['file.txt', 'my file (1).txt', '.hidden', '...', 'tệp-文件.txt', 'a..b']) {
      test('accepts "$ok"', () {
        expect(isSafeRemoteEntryName(ok), isTrue);
      });
    }
  });

  group('safeLocalChild', () {
    test('joins a normal name', () {
      expect(safeLocalChild('/tmp/dest', 'a.txt'), '/tmp/dest/a.txt');
    });

    test('throws UnsafeRemotePathException for traversal and absolute names', () {
      for (final bad in ['../evil', '/abs/x', '..', 'a/..']) {
        expect(() => safeLocalChild('/tmp/dest', bad),
            throwsA(isA<UnsafeRemotePathException>()),
            reason: bad);
      }
    });
  });
}
