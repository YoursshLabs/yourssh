import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/native_chmod.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('native_chmod'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('chmodNative sets owner-only modes', () async {
    final f = File('${tmp.path}/k')..writeAsStringSync('x');
    await chmodNative(f.path, 0x180);
    expect(f.statSync().mode & 0x1ff, 0x180);
  }, skip: Platform.isWindows);

  test('chmodNative throws FileSystemException with errno on failure',
      () async {
    await expectLater(
      chmodNative('${tmp.path}/missing', 0x180),
      throwsA(isA<FileSystemException>()
          .having((e) => e.osError?.errorCode, 'errno', 2)),
    );
  }, skip: Platform.isWindows);
}
