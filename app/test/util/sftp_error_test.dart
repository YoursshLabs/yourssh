import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/sftp_error.dart';

void main() {
  test('maps status codes to sentences, never the raw class name', () {
    for (final code in [2, 3, 4, 6, 7, 8, 5, 99]) {
      final s = describeSftpError(SftpStatusError(code, 'Failure'), name: 'x');
      expect(s, isNot(contains('SftpStatusError')));
      expect(s, isNot(contains('code $code)')));
    }
    expect(describeSftpError(SftpStatusError(2, 'No such file'), name: 'x'),
        '"x" no longer exists.');
    expect(describeSftpError(SftpStatusError(3, ''), name: 'x'),
        'Permission denied for "x".');
  });

  test('existsMessage only when the name is listed', () {
    expect(existsMessage(['a', 'releases'], 'releases'),
        '"releases" already exists.');
    expect(existsMessage(['a'], 'b'), isNull);
  });
}
